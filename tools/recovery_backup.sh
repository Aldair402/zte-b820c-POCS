#!/system/bin/sh
# recovery_backup.sh — image the boot-critical partitions from an Android recovery shell.
#
# Target: ZTE B820C-A15 (Amlogic G12A / U212), 8 GB eMMC, GPT with /dev/block/by-name links.
# Run location: recovery console (UART or `adb shell` in recovery), as root.
#
# Usage:
#   sh /udisk/recovery_backup.sh                 # autodetect the FAT32 stick
#   sh /udisk/recovery_backup.sh /mnt/udisk      # explicit destination
#   sh /udisk/recovery_backup.sh /mnt/udisk full # also dump super + cache (~3.2 GB)
#
# Output: <dest>/bk-<yyyymmdd-hhmm>/<part>.img, MANIFEST.txt, md5sums.txt, misc/ (cmdline, dmesg, dt)
#
# Environment notes (measured on a retail unit, see docs/09):
#   * the recovery shell is uid 0 but SELinux-confined, and `setenforce 0` is DENIED;
#     this script therefore never calls it and only uses operations that pass policy.
#   * /udisk (vfat) is noexec: run this file with `sh /udisk/recovery_backup.sh`
#     (the shell reads it; nothing is exec'd from the stick).
#   * nothing here writes to the eMMC: every operation is read-only.
set -u

SMALL_PARTS="env misc conf dtbo vbmeta boot recovery logo tee param oem metadata cri_data factory bootloader0 bootloader1"
BIG_PARTS="super cache"
ENV_RAW_OFFSET=0x45c00000      # from the bootloader log: "mmc env offset: 0x45c00000"
ENV_RAW_BYTES=1048576          # 1 MB is more than the whole Amlogic env area

log()  { echo "[bk] $*"; }
warn() { echo "[bk] WARN: $*"; }

# ---------------------------------------------------------------- destination
find_dest() {
    for c in /udisk /mnt/udisk /mnt/usb /mnt/usb_storage /storage/usbdisk /usb_disk /sdcard; do
        [ -d "$c" ] || continue
        if ( : > "$c/.bk_write_test" ) 2>/dev/null; then
            rm -f "$c/.bk_write_test"
            echo "$c"
            return 0
        fi
    done
    for c in /mnt/media_rw/* /storage/*; do
        [ -d "$c" ] || continue
        if ( : > "$c/.bk_write_test" ) 2>/dev/null; then
            rm -f "$c/.bk_write_test"
            echo "$c"
            return 0
        fi
    done
    return 1
}

DEST="${1:-}"
MODE="${2:-}"
if [ -z "$DEST" ]; then
    DEST="$(find_dest)" || { echo "[bk] ERROR: no writable destination found; insert a FAT32 stick and pass its mount point"; exit 1; }
fi
[ -d "$DEST" ] || { echo "[bk] ERROR: $DEST is not a directory"; exit 1; }

STAMP="$(date +%Y%m%d-%H%M 2>/dev/null | tr -d ':' || echo manual)"
OUT="$DEST/bk-$STAMP"
mkdir -p "$OUT/misc" || { echo "[bk] ERROR: cannot create $OUT"; exit 1; }

log "destination : $OUT"
log "selinux     : $(getenforce 2>/dev/null || echo unknown)  domain=$(cat /proc/self/attr/current 2>/dev/null)"
log "kernel      : $(uname -r 2>/dev/null)"
log "blockdevs   : $(ls /dev/block/by-name 2>/dev/null | tr '\n' ' ')"
echo

# ---------------------------------------------------------------- environment
{
    echo "date      : $(date 2>/dev/null)"
    echo "uname     : $(uname -a 2>/dev/null)"
    echo "getenforce: $(getenforce 2>/dev/null)"
    echo "cmdline   : $(cat /proc/cmdline 2>/dev/null)"
    echo "partitions:"
    cat /proc/partitions 2>/dev/null
} > "$OUT/MANIFEST.txt" 2>&1

cat /proc/cmdline  > "$OUT/misc/cmdline.txt"   2>/dev/null
dmesg             > "$OUT/misc/dmesg.txt"      2>/dev/null
cp /proc/config.gz "$OUT/misc/config.gz"       2>/dev/null
cp /sys/firmware/fdt "$OUT/misc/live.dtb"      2>/dev/null
ls -l /dev/block/by-name/ > "$OUT/misc/by-name.txt" 2>&1
ls -l /dev/block/        > "$OUT/misc/block.txt"     2>&1

# ---------------------------------------------------------------- partitions
dump_one() {
    part="$1"
    src="/dev/block/by-name/$part"
    dst="$OUT/$part.img"
    [ -e "$src" ] || { warn "$part: no such block device (skipped)"; return 1; }
    log "reading $part ..."
    dd if="$src" of="$dst" bs=1048576 2>/dev/null
    if [ ! -s "$dst" ]; then
        toybox dd if="$src" of="$dst" bs=1048576 2>/dev/null
    fi
    if [ ! -s "$dst" ]; then
        cat "$src" > "$dst" 2>/dev/null
    fi
    if [ -s "$dst" ]; then
        log "  $part.img $(stat -c %s "$dst" 2>/dev/null || echo ?) bytes"
        return 0
    fi
    rm -f "$dst"
    warn "$part: no readable path (dd/toybox/cat all denied) - policy blocks block I/O here"
    return 1
}

log "--- boot-critical partitions ---"
for p in $SMALL_PARTS; do dump_one "$p"; done

if [ "$MODE" = "full" ]; then
    log "--- full mode: super + cache (this takes a while) ---"
    for p in $BIG_PARTS; do dump_one "$p"; done
fi

# raw U-Boot environment at the offset reported by the bootloader, as a cross-check
# against by-name/env (catches a stale GPT or an env area moved by the vendor)
if [ -e /dev/block/mmcblk0 ]; then
    log "reading env area at $ENV_RAW_OFFSET ..."
    dd if=/dev/block/mmcblk0 of="$OUT/env_raw_45c00000.img" bs=512 \
        skip=$((ENV_RAW_OFFSET / 512)) count=$((ENV_RAW_BYTES / 512)) 2>/dev/null
    [ -s "$OUT/env_raw_45c00000.img" ] && log "  env_raw_45c00000.img ok" || warn "raw env dump failed"
fi

# ---------------------------------------------------------------- checksums
log "--- md5sums ---"
( cd "$OUT" && md5sum *.img misc/* 2>/dev/null > md5sums.txt )
cat "$OUT/md5sums.txt" 2>/dev/null

sync
echo
log "done. files in $OUT:"
ls -l "$OUT"
echo
log "verify on the PC:  md5sum -c md5sums.txt"
log "unpack boot:       python3 bootimg_dtb_extract.py boot.img out/"
