# 09 — Recovery mode: root shell for imaging (and what it is not)

Recovery gives a **uid 0 shell on the device** without touching the boot chain. It is the shortest
path to a complete backup of every partition that matters, and it is the recommended first step
before modifying anything.

Confirmed on a retail unit (see `izzi.txt` in the repository root): after the kernel hand-off the
serial console drops to a shell and the recovery ramdisk root is visible:

```
# ls
acct           apex            bin             cache           data
debug_ramdisk  init.recovery.amlogic.rc         sideload        udisk
second_stage_resources         postinstall     vendor_dlkm     ...
#
```

## 9.1 Getting in

| Path | Procedure | Notes |
|------|-----------|-------|
| A. Upgrade/power key | Hold the **power (upgrade) button** while applying power | Reproduced: bootloader prints `detect upgrade key` for `GPIOAO_3 = 0`, then `prk:` key events, then the `#` prompt |
| B. From Android | `svc power reboot recovery` (works as uid 1000 via the factory channel, §02) | Writes the BCB in `misc`; the bootloader honours it on the next boot |
| C. From a PC | `adb devices` while the box is in recovery | Recovery `adbd` runs as root and does not require the authorization dialog |

Path C is the most convenient if a PC is at hand: everything can be pulled with `adb exec-out`
(§9.4). Paths A and B need only the UART link.

## 9.2 Confirmed limits on a retail unit

Measured in the recovery shell of an unmodified B820C-A15:

| Observation | Consequence |
|-------------|-------------|
| `setenforce 0` → **Permission denied** | the policy cannot be relaxed from this shell; there is no permissive mode to fall back on (user build) |
| `/udisk` (vfat) is mounted **noexec** | binaries cannot be executed from the stick, but files **can** be written to it |
| writes to `/udisk` work normally | the stick is a valid destination for images and dumps |
| `adb` in recovery runs as root without the authorization dialog | the PC route needs no policy change at all (§9.4 B) |

Design consequences, applied in `tools/recovery_backup.sh` and `tools/recovery_ladder.txt`:

- The shell is `uid=0` but **SELinux-confined** (`cat /proc/self/attr/current` shows the domain).
  Everything runs *inside* the policy; no attempt is made to disable it.
- Scripts are started as `sh /udisk/recovery_backup.sh` — the shell reads the file, nothing is
  exec'd from the stick, so `noexec` is irrelevant.
- Each partition read has three fallbacks (`dd` → `toybox dd` → `cat`) and the log states which one
  worked, so a partial backup is diagnosed from its own output.
- If block I/O is denied for **all** partitions, the backup does not stop: the sysfs/proc dumps
  (§9.3 step 3 of the ladder) still deliver the boot command line, the partition layout and the
  **live device tree**, which is the input needed for Wi-Fi/IR/LED work. Block images can then be
  taken over adb from the PC.

- `initargs` + `androidboot.selinux=permissive` (via the HAL, §05) is *not* a workaround: user builds
  do not allow a permissive boot, and it is a persistent change. Do not plan around it.

## 9.3 What to image first

Partition sizes as reported by the bootloader (they sum to the 8 GB eMMC):

| Partition | Size | Why it matters |
|-----------|------|----------------|
| `env` | small | U-Boot environment — the hook, `preboot`, `bootcmd`, `ubootdone` |
| `misc` | 8 MB | BCB: boot mode, slot state, `wipe_data`/`wipe_cache` flags |
| `conf` | 4 MB | Amlogic config partition (HDMI mode, `cvbs` settings) |
| `dtbo` | 8 MB | 1 DTBO applied after the base DTB (`apply dtbo 0`) |
| `vbmeta` | 2 MB | AVB metadata; `locked = 1`, verified against the vendor key |
| `boot` | 16 MB | kernel + ramdisk + **the factory DTB** (base for device-tree work) |
| `recovery` | 24 MB | recovery kernel/ramdisk — the image that provides this shell |
| `logo` | 8 MB | boot logos (material table, 480i…1080p) |
| `tee` | 32 MB | OP-TEE / BL32 |
| `param` | 16 MB | Amlogic parameter block |
| `oem` | 16 MB | OEM data |
| `metadata` | 16 MB | encryption/rollback metadata |
| `cri_data` | 8 MB | DRM keys |
| `factory` | 8 MB | factory calibration (uid 1000 cannot read it; root can) |
| `bootloader0/1` | 4 MB ea. | BL2/BL31 + U-Boot (two copies) |
| `super` | 1.76 GB | dynamic partitions (`/system`, `/vendor`, `/product`, `/odm`) |
| `cache` | 1 GB | wiped on every boot, useless as storage |

Full paste-ready command list with per-step fallbacks: [`tools/recovery_ladder.txt`](../tools/recovery_ladder.txt).

`super` and `cache` are optional: the first is reproducible from the OTA package, the second is
volatile. Everything else fits in ~200 MB.

## 9.4 Procedure

### A. Fat32 stick (UART or adb shell)

1. Copy `tools/recovery_backup.sh` from this repository to the root of a FAT32 stick. VFAT mounts
   with `noexec`, so run it through the shell: `sh /udisk/recovery_backup.sh`.
2. In recovery, check that the stick is mounted (`ls /udisk` — `udisk` is the Amlogic recovery mount
   point). If it is empty, look for another mount point (`mount | grep -E 'vfat|usb'`).
3. Run it:

   ```sh
   sh /udisk/recovery_backup.sh              # autodetects /udisk, /mnt/udisk, /mnt/usb …
   sh /udisk/recovery_backup.sh /mnt/udisk full    # include super + cache (~3.2 GB)
   ```

   The script is read-only with respect to the eMMC. It writes
   `bk-<date>/{<part>.img, env_raw_45c00000.img, misc/, MANIFEST.txt, md5sums.txt}`.

### B. PC over USB (fastest)

```console
$ ./tools/recovery_backup_pc.sh ./b820c-backup
== device ==
List of devices attached
0123456789abcdef        recovery
   uid    : uid=0(root) gid=0(root)
   selinux: Enforcing
== partitions ==
--> env
    ok 131072 bytes md5=…
--> boot
    ok 16777216 bytes md5=…
…
```

Each image is verified against the device's own `md5sum` of the block device, so a truncated transfer
cannot pass silently. Use WSL/Git-Bash on Windows (or `cmd /c`), not PowerShell, for binary-safe
redirection.

## 9.5 Verifying the backup

```console
$ md5sum -c b820c-backup/md5sums.txt
$ file b820c-backup/boot.img                  # Android bootimg, or: ANDROID! header
$ python3 bootimg_dtb_extract.py b820c-backup/boot.img out/
$ ls out/                                     # kernel, ramdisk.cpio.gz, dtb/*.dtb
$ python3 -c "import gzip;print(gzip.open('b820c-backup/config.gz').read().decode())" | head -40
```

Also worth keeping with the images: `MANIFEST.txt`, `misc/cmdline.txt`, `misc/dmesg.txt` and
`misc/live.dtb` (a copy of `/sys/firmware/fdt`, the exact DTB the running kernel was handed).

## 9.6 After the backup — options that use this shell

Ranked by how much they modify; the first two are covered elsewhere in this repository:

1. **Factory DTB extraction** from `boot.img` / `dtbo.img` — needed to tune Wi-Fi (MT7663), IR and
   the LED/display nodes for a mainline kernel (`docs/07` in `bootimg_dtb_extract.py` usage).
2. **U-Boot environment analysis** — compare `env.img` against `env_raw_45c00000.img`; the bootloader
   writes the environment at that raw offset, so a mismatch means the GPT copy is stale.
3. **Persistent hooks** — the same `setBootEnv` writes as §06, now re-appliable from recovery if a
   hook is lost.
4. *(Untested)* **`avb2=0`** — the bootloader log shows `CONFIG_AVB2: avb2` and `avb verification:
   locked = 1`. The `avb2` environment variable is the Amlogic switch for AVB verification. Clearing
   it would, in principle, allow a modified `boot` image to run. This has **not** been tried on this
   model: changing it can fail closed and leave the unit unbootable. Any test must come after the
   backup, with the USB Burning Tool and the stock firmware ready.
5. **Flashing a mainline system** — with a verified backup, an eMMC install (`boot` replaced by a
   mainline kernel, `super` replaced by a rootfs) is a recoverable operation instead of a one-way
   door.

## 9.7 Failure modes to expect

| Symptom | Cause | Action |
|---------|-------|--------|
| every `dd` on `/dev/block/*` denied | SELinux blocks block I/O in this domain; `setenforce` is denied too | keep the step 2/3 dumps, then use the PC-over-adb route (§9.4 B) |
| `adb devices` shows nothing in recovery | USB driver / stale server | `adb kill-server`, replug, check the device manager (Amlogic driver) |
| no `#` prompt after `Starting kernel` | key not held during the window, or BCB already consumed | retry, hold the key through the logo |
| `env.img` differs from the raw dump | environment written after the last GPT update | trust `env_raw_45c00000.img` |
| stick not visible in `/udisk` | vfat not mounted by recovery | `mount \| grep -i vfat` to find it; if absent: `mount -t vfat /dev/block/sda1 /udisk` (check `ls /dev/block/sd*`) |
| `sh /udisk/recovery_backup.sh` does nothing | vfat `noexec` misread as "cannot run scripts" | the call above is correct: only `./script` fails, `sh /udisk/script.sh` works |
