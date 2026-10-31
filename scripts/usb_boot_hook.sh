#!/system/bin/sh
# ============================================================================
#  usb_boot_hook.sh — instalador del ARRANQUE POR USB (opcional, reversible)
#
#  Qué hace: añade un paso al final de `preboot` que, SOLO si hay un pendrive
#  FAT32 con `u-boot.ext` en la raíz, carga ese U-Boot moderno y salta a él
#  (así arranca Linux/Armbian del pendrive). Si no hay pendrive, no hace nada.
#
#  Protecciones incluidas:
#    * rescue.flag en el pendrive  -> aborta y arranca Android
#    * disparo único (ubootdone)   -> NO puede entrar en bucle de reinicios
#    * telemetría en `cstep`       -> sabes qué paso se ejecutó, sin cable serie
#
#  Ejecutar con uid 1000 (via /RunCmd -> scripts/runsys.py -f usb_boot_hook.sh)
#  Para deshacer: scripts/disable_usb_boot.sh
#
#  ¡Ojo! El U-Boot de fábrica (2015.01) NO tiene `booti`: por eso se salta al
#  U-Boot moderno del pendrive (u-boot.ext, presente en las imágenes de TV-box).
# ============================================================================
set -u

HAL="${HAL:-/data/local/tmp/hal.jar}"            # cliente HAL (ver scripts/hal.sh)
BIN() { CLASSPATH="$HAL:/vendor/framework/droidlogic.software.core.jar" \
        /system/bin/app_process /system/bin \
        vendor.amlogic.hardware.systemcontrol.V1_0.HalCall "$@" 2>/dev/null | tail -1; }
E()  { BIN envset ubootenv.var."$1" "$2" >/dev/null; echo "  $1 = $(BIN envget ubootenv.var."$1")"; }

echo "=== instalando hook USB-only (v7) ==="

HOOK='setenv cstep v7_ini;saveenv;if test ${ubootdone} = 1; then setenv cstep v7_skip;saveenv;else usb start;setenv cstep v7_usb;saveenv;if fatload usb 0:1 ${loadaddr} rescue.flag; then setenv cstep v7_RESCUE;saveenv;else if fatload usb 0 0x1000000 u-boot.ext; then setenv cstep v7_jump0;setenv ubootdone 1;saveenv;go 0x1000000;else if fatload usb 0:1 0x1000000 u-boot.ext; then setenv cstep v7_jump1;setenv ubootdone 1;saveenv;go 0x1000000;else setenv cstep v7_nobootext;saveenv;fi;fi;fi;fi'

PREBOOT='run bcb_cmd; run factory_reset_poweroff_protect;run upgrade_check;run init_display;run storeargs;run upgrade_key;bcb uboot-command;run switch_bootmode;run cachebootcheck;'

E cachebootcheck "$HOOK"
E preboot        "$PREBOOT"
E ubootdone      0
E cstep          armado_v7

sync
echo
echo "=== resumen ==="
echo "  preboot        = $(BIN envget ubootenv.var.preboot)"
echo "  cachebootcheck = $(BIN envget ubootenv.var.cachebootcheck)"
echo
echo "Ahora: mete el pendrive (con u-boot.ext + uEnv.txt + zImage + uInitrd + dtb) y reinicia."
echo "Para volver a Android en cualquier momento: quita el pendrive, o usa rescue.flag."
