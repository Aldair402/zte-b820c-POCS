# 05 — Amlogic `system_control` HAL: root-owned boot environment access

## 5.1 Service

```
vendor.amlogic.hardware.systemcontrol@1.0::ISystemControl      (also @1.1)
daemon    systemcontrol            (root, SELinux u:r:hal_systemcontrol_default:s0)
libs      /vendor/lib/hw/android.hardware... (vendor image), droidlogic.software.core.jar
```

Process facts collected on the test unit: `CapEff=0x3fffffffff`, `Seccomp=0`.

## 5.2 Interface (from the vendor jar)

```java
interface ISystemControl {
    void getProperty(String k, getPropertyCallback cb);
    void getPropertyString(String k, String def, getPropertyStringCallback cb);
    int  setProperty(String k, String v);
    void readSysfs(String path, readSysfsCallback cb);
    int  writeSysfs(String path, String value);
    int  writeSysfsBin(String path, int[] data, int n);
    void getBootEnv(String name, getBootEnvCallback cb);
    void setBootEnv(String name, String value);          // <-- U-Boot environment write
    int  writeUnifyKey(String key, String value);
    void readUnifyKey(String key, readUnifyKeyCallback cb);
    void loopMountUnmount(int mount, String path);
    int  updataLogoBmp(String path);
    int  writeHdcpRXImg(String path);
}
```

`getBootEnv`/`setBootEnv` map to the Amlogic `ubootenv` reader/writer (`ubootenv.var.<name>`), which
rewrites the `env` partition with a correct CRC.

## 5.3 PoC

Java client: [`poc/04_hal_envset/`](../poc/04_hal_envset/). Build with `d8` and run through
`app_process` (no APK, no root):

```console
$ adb push hal.jar /data/local/tmp/ && adb push HalEnvset.jar /data/local/tmp/
$ adb shell 'CLASSPATH=/data/local/tmp/HalEnvset.jar:/data/local/tmp/hal.jar \
   /system/bin/app_process /system/bin HalEnvset envget ubootenv.var.bootcmd'
getBootEnv(ubootenv.var.bootcmd) rc=0 val=bootsys

$ adb shell 'CLASSPATH=… app_process /system/bin HalEnvset envset ubootenv.var.foo bar'
setBootEnv done
```

## 5.4 Persistence matrix (measured)

| Variable | Survives reboot? | Note |
|----------|------------------|------|
| `preboot`, `cachebootcheck`, custom `ubootenv.var.*` | **yes** | usable as a boot hook (§06) |
| `bootcmd` | **no** — reset to `bootsys` | vendor anti-brick restore |
| `EnableSelinux` | **no** — reset to `enforcing` | same mechanism |
| `initargs` / `bootargs` | used at boot by `storeargs` | `androidboot.*=1` injected here reaches the kernel (`ro.boot.*`) |
| `bootdelay` | yes | useful to gain time in the U-Boot console (§07) |

## 5.5 Other verbs — observed behavior

| Verb | Observation |
|------|-------------|
| `readSysfs` on `/proc/device-tree/*` | returns strings (used to fingerprint the board) |
| `readSysfs` on `/dev/block/*` | returns `-32` (not a sysfs path) |
| `writeSysfs` / `writeSysfsBin` | accepts sysfs paths; no `O_CREAT`; `rc=0` does not imply success |
| `writeUnifyKey` | not exercised (efuse-backed; writing can brick the unit) |
| `loopMountUnmount` | malformed arguments crash the daemon (`SIGSEGV`) — no argument validation |
| `updataLogoBmp` | accepts a BMP path |
| `setProperty` | constrained to HAL-owned properties |

## 5.6 Impact

`setBootEnv` is equivalent to boot-path control: `root=`, `init=`, `preboot`, and the whole U-Boot
console environment are selectable from an unprivileged app through a chain of two components. With
USB/serial access this becomes arbitrary code execution as root before Android starts.

## 5.7 Fix

- Require a signature-level permission (`system|signature`) or attestation for `setBootEnv`,
  `writeUnifyKey`, `loopMountUnmount`, and the generic `writeSysfs*` calls.
- Validate all arguments of `loopMountUnmount` (the SIGSEGV is proof of missing validation).
- Treat `preboot`/`bootcmd`/`initargs` as immutable from Android.

## 5.8 The vendor policy opens this HAL to untrusted applications

The strongest part of the exposure is in the SELinux policy shipped on the unit, with `untrusted_app`
as the **source**:

```
(allow untrusted_app_29_31_0 system_control (binder (call)))
(allow untrusted_app_31_0    system_control (binder (call)))
```

i.e. the root-owned HAL that carries `setBootEnv()` is deliberately reachable by binder from
unprivileged applications. The HAL performs no permission or attestation check of its own, so nothing
else gates the call, and the daemon legitimately holds the environment block device open for writing:

```
(allow system_control env_device (blk_file (read write getattr open)))
(allow system_control system_app_31_0   (binder (call)))
(allow system_control platform_app_31_0 (binder (call)))
```

Two consequences for the fix:

- The policy itself is part of the attack surface. Granting `binder call` from `untrusted_app` (or from
  any app domain) to a HAL that writes the boot environment nullifies any permission check that the HAL
  might add later; the rule must be narrowed to the domains that legitimately need the interface
  (`system_app`/`platform_app`), and preferably to an attestation-gated service.
- The empirical behaviour matches: from uid 1000 the calls return `rc=0`; from the shell domain the
  same calls abort, which is consistent with the rules above rather than with an interface-level check.
