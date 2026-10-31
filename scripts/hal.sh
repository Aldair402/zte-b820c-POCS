#!/system/bin/sh
# ============================================================================
#  hal.sh — envoltorio del HAL root de Amlogic (system_control)
#
#  Permite, desde uid 1000 (system_app), hablar con el daemon root
#  "systemcontrol" y usar:
#      envget <var>            leer variable de entorno de U-Boot
#      envset <var> <valor>    ESCRIBIR variable de U-Boot  (persistente)
#      rs <ruta>               readSysfs  (root)
#      ws <ruta> <valor>       writeSysfs (root)
#      setprop <k> <v>         setProperty (contexto de la HAL)
#      ukr <clave>             readUnifyKey
#
#  Requisitos:
#    - hal.jar en el dispositivo (cliente Java compilado para esta HAL).
#      Si no lo tienes, compílalo con `d8` desde el AIDL del vendor
#      (droidlogic.software.core.jar / ISystemControl) — ver docs/05.
#
#  Ejemplo:
#      hal.sh envget ubootenv.var.bootcmd
#      hal.sh envset ubootenv.var.mivariable "hola"
# ============================================================================
set -u

HALJAR="${HALJAR:-/data/local/tmp/hal.jar}"
VENDOR_JAR="/vendor/framework/droidlogic.software.core.jar"
MAIN="vendor.amlogic.hardware.systemcontrol.V1_0.HalCall"

if [ ! -f "$HALJAR" ]; then
  echo "[!] No encuentro el cliente HAL en $HALJAR"
  echo "    (define HALJAR=/ruta/hal.jar o copia hal.jar al dispositivo)"
  exit 1
fi

CLASSPATH="$HALJAR:$VENDOR_JAR" \
  /system/bin/app_process /system/bin "$MAIN" "$@" 2>/dev/null | tail -1

# Nota: los mensajes "UnsatisfiedLinkError: libandroidicu.so / libhwbinder.so"
# son RUIDO normal del cliente en algunos firmwares; el resultado sale al final.
