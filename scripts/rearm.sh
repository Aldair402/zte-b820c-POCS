#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  rearm.sh — deja lista la "primitiva 1" en la caja (ejecutar DENTRO de Termux,
#  en el propio TV box). No necesita PC ni tocar la TV.
#
#  Qué hace:
#    1) comprueba que adb local está conectado (si no: adb connect 127.0.0.1:5555)
#    2) lanza la app de fábrica con un broadcast exportado
#    3) envía la "trama mágica" al servicio de 10044 -> arranca su HTTPServer :10001
#    4) verifica que /RunCmd responde (uid 1000)
#
#  Requisitos: Termux con android-tools (adb) y curl.
# ============================================================================
export PATH=$PATH:/data/data/com.termux/files/usr/bin
set -u

ADB="adb -s 127.0.0.1:5555"
DEV_IP="127.0.0.1"

echo "=== 1. adb local ==="
adb connect ${DEV_IP}:5555 2>&1 | tail -1
sleep 2
$ADB shell true </dev/null 2>/dev/null || { echo "[!] adb no responde. ¿Habilitado? Ver scripts/adb_enable.sh"; exit 1; }

echo "=== 2. broadcast (arranca FactoryTest + MyService) ==="
$ADB shell 'am broadcast -a com.zte.stb.StartHWTest' </dev/null 2>&1 | tail -1

echo "=== 3. esperar el puerto 10044 ==="
ok=0
for i in $(seq 1 20); do
  if (exec 3<>/dev/tcp/${DEV_IP}/10044) 2>/dev/null; then ok=1; exec 3<&- 3>&-; echo "10044 abierto (${i}s)"; break; fi
  sleep 1
done
[ "$ok" = 1 ] || { echo "[!] 10044 no abre"; exit 1; }

echo "=== 4. trama mágica (7e 01 2c ff + 43x00 + 7e) ==="
exec 3<>/dev/tcp/${DEV_IP}/10044
printf '\x7e\x01\x2c\xff' >&3
for _ in $(seq 1 43); do printf '\x00' >&3; done
printf '\x7e' >&3
sleep 4
exec 3<&- 3>&- 2>/dev/null

echo "=== 5. verificar RunCmd (:10001) ==="
curl -s -m 10 -X POST -H 'Content-Type: application/json' \
  -d '{"dictData":{"shellCmd":"id","requestRst":"true"}}' \
  "http://${DEV_IP}:10001/RunCmd" | head -c 400
echo
echo "=== LISTO: usa scripts/runsys.py para ejecutar como uid 1000 ==="
