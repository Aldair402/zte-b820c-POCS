#!/system/bin/sh
# 02_adb_authorize.sh — add an ADB public key to adbd's allowlist without the on-screen dialog.
#
# Mechanism
#   IAdbManager (service "adb") transaction 1 is allowDebugging(boolean, String).
#   `service call` performs the binder transaction as the caller; on the affected build the
#   call is accepted and AdbDebuggingManager stores the key in its allowlist (the same store the
#   Settings dialog writes to). adbd then accepts that key over TCP.
#
# Preconditions
#   - run on the device itself (adb shell, or /RunCmd as system_app)
#   - device must have the adb daemon service present (always true on Android)
#
# Result
#   shell access: uid=2000(shell), persists across reboots because
#   persist.sys.usb.config=adb restarts adbd in TCP mode and the key stays authorized.
set -u
KEYFILE="${1:-/data/local/tmp/adbkey.pub}"

if [ ! -f "$KEYFILE" ]; then
  echo "usage: $0 /path/to/adbkey.pub   (create with: adb keygen adbkey)"
  exit 1
fi

PUB="$(cat "$KEYFILE")"
echo "[*] authorizing key: $(echo "$PUB" | cut -c1-40)..."

# tx=1, alwaysAllow=true(i32 1), publicKey as a UTF-16 string (s16)
service call adb 1 i32 1 s16 "$PUB" 2>&1 | head -3

echo "[*] enabling adbd on TCP"
setprop persist.sys.usb.config adb
setprop service.adb.tcp.port 5555 2>/dev/null || true
sleep 3

echo "[*] connecting"
adb connect 127.0.0.1:5555 2>&1 | tail -2 || echo "  (run 'adb connect 127.0.0.1:5555' manually)"

echo "[*] verifying"
adb -s 127.0.0.1:5555 shell id </dev/null 2>&1 | tail -1
