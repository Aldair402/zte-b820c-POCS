#!/system/bin/sh
# ============================================================================
#  app_perms.sh — concede a una app los permisos que este firmware le niega.
#
#  Contexto (ZTE B820C-A15, Android 12): el ROM trae el appop
#  REQUEST_INSTALL_PACKAGES en "deny" para apps de usuario y esconde el toggle
#  por-app. Cualquier app que instale sus propios añadidos (las EXTENSIONES de
#  Aniyomi son APKs aparte) falla sin decir por qué.
#
#  Uso:
#     sh app_perms.sh                 # autodetecta Aniyomi
#     sh app_perms.sh <pkg> [<pkg>]   # paquetes explícitos
#
#  Ejecutar como uid 2000 (adb shell) o uid 1000 (canal de fábrica /RunCmd).
#  `pm grant` necesita contexto shell/root.
# ============================================================================
set -u
SELF="$(basename "$0")"

# IDs reales verificados contra el build.gradle.kts y el APK de aniyomiorg:
#   release -> xyz.jmir.tachiyomi.mi        (anime+manga, el APK "aniyomi-*.apk")
#   debug   -> xyz.jmir.tachiyomi.mi.debug
# Ojo: el namespace interno es eu.kanade.tachiyomi, pero el applicationId NO.
detect() {
  for cand in xyz.jmir.tachiyomi.mi xyz.jmir.tachiyomi.mi.debug; do
    pm path "$cand" >/dev/null 2>&1 && echo "$cand"
  done
  # respaldo: cualquier fork de la familia que esté instalado
  pm list packages 2>/dev/null | sed 's/^package://' \
    | grep -iE 'jmir|aniyomi|kanade\.tachiyomi|tachiyomi\.(ani|mi)|miru' | sort -u
}

PKGS="${*:-}"
[ -z "$PKGS" ] && PKGS="$(detect)"

if [ -z "$PKGS" ]; then
  echo "No encontré la app. Paquetes de terceros instalados:"
  pm list packages -3 2>/dev/null | sed 's/^package://' | sort | head -30
  echo
  echo "Pásame el paquete a mano:  sh $SELF <package.name>"
  exit 1
fi

OPS="REQUEST_INSTALL_PACKAGES MANAGE_EXTERNAL_STORAGE LEGACY_STORAGE WAKE_LOCK RUN_IN_BACKGROUND"
PERMS="android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.POST_NOTIFICATIONS"

echo "objetivo(s): $PKGS"
echo

for P in $PKGS; do
  echo "=============================================================="
  echo " paquete : $P"
  echo " ruta    : $(pm path "$P" 2>/dev/null | head -1)"
  echo "=============================================================="

  echo "-- appops"
  for op in $OPS; do
    if cmd appops set "$P" "$op" allow 2>/dev/null; then
      val="$(cmd appops get "$P" "$op" 2>/dev/null | head -1 | sed 's/^[A-Z_]*: //')"
      printf '   %-24s -> %s\n' "$op" "${val:-?}"
    else
      printf '   %-24s -> no soportado\n' "$op"
    fi
  done

  echo "-- permisos de ejecución (pm grant)"
  for perm in $PERMS; do
    out="$(pm grant "$P" "$perm" 2>&1)"
    if [ -z "$out" ]; then printf '   %-46s -> OK\n' "$perm"
    else printf '   %-46s -> %s\n' "$perm" "$(echo "$out" | head -1)"; fi
  done

  echo "-- batería (evita que maten descargas largas)"
  dumpsys deviceidle whitelist "+$P" >/dev/null 2>&1 \
    && echo "   whitelist OK" || echo "   whitelist: sin permiso DUMP"

  echo "-- reinicio para que tome efecto"
  am force-stop "$P" 2>/dev/null && echo "   force-stop OK"

  echo "-- estado final"
  cmd appops get "$P" REQUEST_INSTALL_PACKAGES 2>/dev/null | sed 's/^/   /'
  cmd appops get "$P" MANAGE_EXTERNAL_STORAGE  2>/dev/null | sed 's/^/   /'
  echo
done

echo "hecho."
