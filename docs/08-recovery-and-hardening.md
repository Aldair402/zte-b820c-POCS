# 08 — Recovery procedure and hardening notes

> Before modifying anything: back up the partitions from a recovery shell — see [09-recovery-mode.md](09-recovery-mode.md).

## 8.1 Kill-switch

The USB hook (§06) checks for a file on the FAT32 stick before doing anything:

```
if fatload usb 0:1 ${loadaddr} rescue.flag; then setenv cstep v7_RESCUE; saveenv; fi
```

Create it on Windows: Notepad → contents `RESCUE` → *Save as* → type **All files** → name
**`"rescue.flag"`** (quotes prevent `.txt`) → root of the FAT32 volume.

## 8.2 Exiting a boot loop

| State | Action |
|-------|--------|
| black screen / repeated reboots | power off ≥ 30 s, power on → Android (single-shot guard) |
| USB stick inserted with `rescue.flag` | Android forced |
| both fail | PC + USB cable + **Amlogic USB Burning Tool** with stock firmware |

## 8.3 Reverting the U-Boot environment

`poc/06_disable_usb_boot.sh` restores:

```
preboot          = run bcb_cmd; run factory_reset_poweroff_protect;run upgrade_check;run init_display;
                   run storeargs;run upgrade_key;bcb uboot-command;run switch_bootmode;
cachebootcheck   = echo cachebootcheck_desactivado
cacheroot_enable = 0        ubootdone = 0        ctry = 0
EnableSelinux    = enforcing
rm -f /cache/rplgo /cache/recovery/rootnow.txt
```

`bootcmd` returns to `bootsys` by itself (vendor restore path).

## 8.4 Failure modes encountered (field notes)

1. `/cache/recovery/*` is wiped on every boot (OTA cleanup). Payloads placed there disappear; the
   resulting `init=` failure produces a kernel panic and a boot loop until counters stop it.
2. `bootcmd` and `EnableSelinux` are restored on boot; `preboot` is not. Hooks belong in `preboot`.
3. An external `init=` (`/dev/mmcblk0p3` + `skip_initramfs`) is not executed on this kernel/U-Boot
   combination — panic before userspace.
4. Executable bits in `/cache` require `install -m 0755`; `cp` creates `0600` and `chmod` is denied.
5. Remote-management tunnels (used for the research) expire and die on reboot: verify channel health
   *before* issuing a reboot, and keep an out-of-band recovery path.
6. `rmmod`-style verification of the kernel's Wi-Fi driver is not possible from Android; module
   availability was verified offline from the image's module tree.

## 8.5 Hardening recommendations

For the vendor/operator, in order of impact:

1. `TestToolBroadcast`: `android:exported="false"` (or signature permission) and caller validation;
   never start the HTTP server implicitly from a socket trigger.
2. `IAdbManager.allowDebugging`: enforce `MANAGE_DEBUGGING` *and* the on-screen token flow; restrict
   binder access to the `adb` service by SELinux for untrusted domains.
3. `ISystemControl`: signature/attestation gate on `setBootEnv`, `writeUnifyKey`, `loopMountUnmount`,
   `writeSysfs*`; validate arguments (the `SIGSEGV` proves they are unchecked).
4. Immutable U-Boot variables from Android: `preboot`, `bootcmd`, `initargs`, `bootdelay`.
5. U-Boot: `CONFIG_AUTOBOOT_KEYED`, `bootdelay` 0/negative, and a signed `bootcmd` if the console must
   not be reachable.
6. Do not force `REQUEST_INSTALL_PACKAGES=deny` appop for user-installed packages without exposing the
   per-app toggle.
7. Restore a strict `system_app` SELinux policy for factory components that are not required in
   production builds (factory test APKs should not ship on retail units).

## 8.6 Verification checklist for a patched build

```sh
# 1. broadcast must not start the factory activity from an unprivileged app
am broadcast -a com.zte.stb.StartHWTest ; dumpsys activity activities | grep -i factorytesttool

# 2. adb service must not accept the allowDebugging call from shell/system_app
service call adb 1 i32 1 s16 "$(cat ~/.android/adbkey.pub)"

# 3. HAL must reject setBootEnv for non-system callers
CLASSPATH=/data/local/tmp/HalEnvset.jar:… app_process /system/bin HalEnvset \
  envset ubootenv.var.test 1

# 4. appop default
cmd appops get com.example.downloader REQUEST_INSTALL_PACKAGES
```

Expected on fixed firmware: (1) no activity start, (2) `SecurityException`, (3) `Permission denied`,
(4) `allow` or the toggle available in Settings.
