#!/system/bin/sh
# 03_enable_install.sh — re-enable APK sideloading.
#
# The ROM ships the per-app appop REQUEST_INSTALL_PACKAGES set to "deny" and does not expose the
# *Allow from this source* toggle in Settings. Setting the appop to "allow" restores normal
# installation for the listed packages.
#
# Run as uid 1000 (via /RunCmd) or uid 2000 (adb shell).
set -u

PKGS="
com.esaba.downloader
com.yablio.sendfilestotv
com.termux
com.android.vending
com.spocky.projengmenu
com.android.documentsui
"

echo "== appop REQUEST_INSTALL_PACKAGES -> allow =="
for p in $PKGS; do
  cmd appops set "$p" REQUEST_INSTALL_PACKAGES allow 2>/dev/null
  printf '%-34s %s\n' "$p" "$(cmd appops get "$p" REQUEST_INSTALL_PACKAGES 2>/dev/null | head -1)"
done

echo
echo "== related globals (may need a privileged caller; failures are non-fatal here) =="
settings put secure install_non_market_apps 1 2>/dev/null
echo "install_non_market_apps = $(settings get secure install_non_market_apps 2>/dev/null)"

echo
echo "== installing an APK from the command line =="
cat <<'EOF'
  # uid 1000: APK must be readable by the installer (SELinux labels matter)
  pm install -r /sdcard/Download/app.apk

  # uid 2000: also works from /data/local/tmp
  adb install -r /data/local/tmp/app.apk
EOF

echo
echo "== remaining denials =="
for p in $PKGS; do
  cmd appops get "$p" REQUEST_INSTALL_PACKAGES 2>/dev/null | grep -q deny && echo "still denied: $p"
done
echo done
