#!/system/bin/sh
# ============================================================================
#  fix_install_perms.sh — PERMISOS DE INSTALADOR (instalar APKs de terceros)
#
#  Causa del bloqueo (medida en ZTE B820C-A15): el appop
#  REQUEST_INSTALL_PACKAGES viene en "deny" para las apps de usuario, así que el
#  instalador rechaza cualquier APK que no venga del Play Store.
#
#  Solución: ponerlo en "allow" (y quitar verificadores) por app.
#
#  Ejecutar como uid 1000 (via /RunCmd) o uid 2000 (adb shell).
#  Añade/quita paquetes en la lista PACKAGES según tus apps descargadoras.
# ============================================================================
set -u

PACKAGES="
com.esaba.downloader
com.yablio.sendfilestotv
com.termux
com.android.vending
com.spocky.projengmenu
com.android.documentsui
"

echo "=== 1. appops REQUEST_INSTALL_PACKAGES -> allow ==="
for P in $PACKAGES; do
  cmd appops set "$P" REQUEST_INSTALL_PACKAGES allow 2>/dev/null
  R="$(cmd appops get "$P" REQUEST_INSTALL_PACKAGES 2>/dev/null | head -1)"
  printf '%-32s %s\n' "$P" "${R:-(paquete no instalado)}"
done

echo
echo "=== 2. ajustes relacionados ==="
# (settings put puede fallar para uid 1000 en algunos firmwares: es normal)
settings put secure install_non_market_apps 1 2>/dev/null
echo "install_non_market_apps = $(settings get secure install_non_market_apps 2>/dev/null)"

echo
echo "=== 3. cómo instalar un APK por línea de comandos ==="
cat <<'EOF'
  # coloca el APK en /sdcard/Download y luego:
  pm install -r /sdcard/Download/miapp.apk          # uid 1000
  adb install -r /sdcard/Download/miapp.apk         # uid 2000 (o /data/local/tmp)
EOF

echo
echo "=== 4. comprobación rápida (¿hay algo en deny todavía?) ==="
for P in $PACKAGES; do
  cmd appops get "$P" REQUEST_INSTALL_PACKAGES 2>/dev/null | grep -q deny && echo "OJO: $P sigue en deny"
done
echo "hecho."
