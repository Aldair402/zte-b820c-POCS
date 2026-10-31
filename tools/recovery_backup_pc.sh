#!/usr/bin/env bash
# recovery_backup_pc.sh — pull the boot-critical partitions off the box from a PC, via adb, while
# the device is sitting in recovery.
#
# Why recovery: adbd in recovery runs as root and does not require the on-screen authorization
# dialog, so this is the shortest path to a full image of every partition that matters.
#
# Requirements: android-tools (adb) on the PC, USB cable, and a booted recovery (see docs/09).
#
# Usage:
#   ./recovery_backup_pc.sh [outdir] [full]
#     outdir  default: ./b820c-backup-<date>
#     full    also pull super and cache (~3.2 GB)
#
# Windows: run this from WSL or Git-Bash. In cmd.exe, `adb exec-out ... > file` is binary-safe;
# PowerShell is not (use `cmd /c` there).
set -euo pipefail

OUT="${1:-b820c-backup-$(date +%Y%m%d-%H%M)}"
MODE="${2:-}"

SMALL="env misc conf dtbo vbmeta boot recovery logo tee param oem metadata cri_data factory"
BIG="super cache"

command -v adb >/dev/null || { echo "adb not found"; exit 1; }

echo "== device =="
adb devices
adb wait-for-device
echo
echo "   serial : $(adb get-serialno)"
echo "   state  : $(adb shell 'getprop ro.boot.mode 2>/dev/null; uname -r' 2>/dev/null | tr '\n' ' ')"
echo "   uid    : $(adb shell id 2>/dev/null | tr -d '\r')"
echo "   selinux: $(adb shell getenforce 2>/dev/null | tr -d '\r')"
echo
echo "If uid is not root or 'getenforce' is denied, you are not in recovery (see docs/09)."
echo

mkdir -p "$OUT"
: > "$OUT/adb-info.txt"
adb shell 'uname -a; getenforce; cat /proc/cmdline; ls -l /dev/block/by-name' \
    >> "$OUT/adb-info.txt" 2>&1 || true

pull_one() {
    local p="$1" f="$OUT/$p.img" dev_md5 local_md5
    echo "--> $p"
    if ! adb exec-out "dd if=/dev/block/by-name/$p bs=1048576 2>/dev/null" > "$f"; then
        echo "    FAILED (partition missing or SELinux denial)"; rm -f "$f"; return
    fi
    [ -s "$f" ] || { echo "    empty"; rm -f "$f"; return; }
    dev_md5="$(adb shell "md5sum /dev/block/by-name/$p 2>/dev/null" | awk '{print $1}' | tr -d '\r')"
    local_md5="$(md5sum "$f" | awk '{print $1}')"
    if [ -n "$dev_md5" ] && [ "$dev_md5" != "$local_md5" ]; then
        echo "    MD5 MISMATCH device=$dev_md5 local=$local_md5"
    else
        echo "    ok $(stat -c %s "$f") bytes md5=$local_md5"
    fi
}

echo "== partitions =="
for p in $SMALL; do pull_one "$p"; done
if [ "$MODE" = "full" ]; then
    echo "== full mode: super + cache =="
    for p in $BIG; do pull_one "$p"; done
fi

echo
echo "== u-boot env, raw area (cross-check against env.img) =="
adb exec-out "dd if=/dev/block/mmcblk0 bs=512 skip=2285568 count=2048 2>/dev/null" \
    > "$OUT/env_raw_45c00000.img" || echo "    failed (needs raw mmcblk0 access)"

echo
echo "== misc =="
adb shell dmesg                > "$OUT/dmesg.txt"   2>/dev/null || true
adb exec-out "cat /proc/config.gz" > "$OUT/config.gz" 2>/dev/null || true
adb exec-out "cat /sys/firmware/fdt" > "$OUT/live.dtb" 2>/dev/null || true

( cd "$OUT" && md5sum *.img > md5sums.txt 2>/dev/null || true )
echo
echo "== result =="
ls -l "$OUT"
echo
echo "next:"
echo "  md5sum -c $OUT/md5sums.txt"
echo "  python3 bootimg_dtb_extract.py $OUT/boot.img out/     # factory DTB for WiFi/IR/LED work"
echo "  python3 -c \"import gzip,sys;print(gzip.open('$OUT/config.gz').read().decode()[:2000])\""
