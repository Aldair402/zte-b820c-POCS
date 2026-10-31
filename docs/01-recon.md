# 01 — Reconnaissance

Collected on the device without root, first from an ordinary app (Termux, uid 10xxx) and later from
`shell` (uid 2000) and `system_app` (uid 1000). This step determines which escalation paths exist
before attempting anything.

## 1.1 Identity

| Field | Value |
|-------|-------|
| Product | ZTE/izzi `B820C-A15`, board `franklin` |
| SoC | Amlogic S905X2 (G12A), chipid `1000B0E370C5A8D7` |
| Board | Amlogic **U212** — `amlogic-dt-id=g12a_u212_mtk`, `compatible=amlogic, g12a` |
| Android | 12 (SDK 31), `SC.eng.ztestb.20250103.234813` / `V83511301.2070` |
| Kernel | `4.9.269 #1 SMP PREEMPT`, userspace ABI **armv8l** (32-bit) |
| Bootloader | U-Boot `2015.01-g65bcffe-dirty`, `bootdelay=1` |
| Verified boot | AVB green, `ro.boot.veritymode=enforcing`, `ro.boot.vbmeta.device_state=locked` |
| SELinux | enforcing |
| Wi-Fi/BT | MediaTek MT7663 (SDIO): `ro.vendor.product.wifi=MTK7661`, `wlan_mt7663_sdio.ko`, `btmtksdio.ko` |
| Ethernet | `eth0` present (100 Mbit, internal PHY) |
| Wi-Fi net | `wlan0 192.168.100.50/24`, gateway 192.168.100.1 |

## 1.2 Listening sockets (loopback scan)

Scanned from an app with bash (`/dev/tcp`; Android's `sh` has no TCP redirection):

| Port | Owner uid | Component |
|------|-----------|-----------|
| 5555 | shell | `adbd` (after §03) |
| 5001 | 1000 | system app |
| 8022 | 10xxx | `sshd` (Termux) |
| 8008/8009/8443/9000 | 10045 | vendor apps |
| 9080 | — | NRDP `2026.1.6.0` |
| **10001** | 1000 | OEM HTTP server (`/RunCmd`) |
| **10042** | 10045 | STBCFG (AES handshake) |
| **10044** | 1000 | OEM `MyService` (frame-command surface) |
| 30000 | 0 | root daemon |
| 33047/37599/6466/6467 | 10045/10049 | vendor |

## 1.3 Storage

```
dm-4 /  dm-5 /vendor  dm-6 /product  dm-7 /odm     (ro, dynamic partitions)
/data      ext4 rw
/metadata  ext4 rw
/cache     ext4 rw  errors=panic
/factory   vfat noexec
```

`/dev/block/by-name`: `boot bootloader0 bootloader1 cache conf cri_data dtbo env factory logo metadata
misc oem param recovery reserved super tee userdata vbmeta` (+ `mmcblk0`, `boot0/1`, `rpmb`).

maj:min (179:x): cache 3, env 4, recovery 6, misc 7, dtbo 9, boot 12, metadata 14, vbmeta 15,
factory 17, super 18, userdata 19.

## 1.4 Kernel configuration (from `config.gz`)

- Present: `EXT4` (encryption/POSIX ACL), `VFAT`, `BLK_DEV_INITRD` + `RD_GZIP`, `DEVTMPFS`,
  `BINFMT_ELF/SCRIPT`, `LOOP`, `SELINUX` (`DEVELOP=y`), `MODULES=y` **without** `MODULE_SIG`,
  `KALLSYMS_ALL`, `RANDOMIZE_BASE`, `ARM64=y`.
- Absent: `USER_NS`, `KPROBES`, `DEVMEM`, `PROC_KCORE`.

Kernel is arm64 while userspace is 32-bit — relevant when shipping helpers (use `aarch64` static
binaries for initramfs work, `arm` for anything executed by Android).

## 1.5 Denials observed before escalation (no root)

| Attempt | Result |
|---------|--------|
| `setenforce 0`, read `/proc/kallsyms`, `/proc/cmdline`, `dmesg` | denied (uid 2000) |
| `su`, SUID/SGID binaries, file capabilities | none present |
| write `/data/misc/adb/adb_keys` | denied (uid 1000 as well) |
| read `/dev/block/*`, `/vendor/firmware/*` | denied (list only) |
| `mkdir /cache`, `/metadata`, `/mnt/vendor/*` | denied |

Device has no compiler: helpers are cross-built off-device (Java via `d8`, C via aarch64/arm gcc) and
pushed over the network. `/data/local/tmp` is executable by uid 2000 and is the working directory for
pushed tools.
