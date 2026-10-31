#!/system/bin/sh
# ============================================================================
#  disable_usb_boot.sh — DESHACE todo el entorno de arranque modificado.
#  Deja la caja como salió de fábrica (arranque Android normal) en 10 segundos.
#
#  Ejecutar con uid 1000 (via /RunCmd -> scripts/runsys.py -f disable_usb_boot.sh)
# ============================================================================
set -u

HAL="${HAL:-/data/local/tmp/hal.jar}"
BIN() { CLASSPATH="$HAL:/vendor/framework/droidlogic.software.core.jar" \
        /system/bin/app_process /system/bin \
        vendor.amlogic.hardware.systemcontrol.V1_0.HalCall "$@" 2>/dev/null | tail -1; }
E()  { BIN envset ubootenv.var."$1" "$2" >/dev/null; echo "  $1 = $(BIN envget ubootenv.var."$1")"; }

echo "=== 1. preboot: valor de fábrica (sin el hook) ==="
E preboot 'run bcb_cmd; run factory_reset_poweroff_protect;run upgrade_check;run init_display;run storeargs;run upgrade_key;bcb uboot-command;run switch_bootmode;'

echo "=== 2. cachebootcheck: neutralizado ==="
E cachebootcheck 'echo cachebootcheck_desactivado'

echo "=== 3. banderas/contadores ==="
E cacheroot_enable 0
E ubootdone        0
E ctry             0
E cstep            desactivado

echo "=== 4. SELinux: valor de fábrica ==="
E EnableSelinux enforcing

echo "=== 5. banderas del payload en /cache ==="
rm -f /cache/rplgo /cache/recovery/rootnow.txt 2>/dev/null
ls /cache/rplgo 2>&1 | tail -1

echo "=== 6. bootcmd (el fabricante ya lo restaura solo) ==="
echo "  bootcmd = $(BIN envget ubootenv.var.bootcmd)"

sync
echo
echo "LISTO: la caja arrancará Android normal. (El pendrive de rescate ya no es necesario.)"
