#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  adb_enable.sh — HABILITADOR DE ADB sin PC y sin diálogo en pantalla
#  Ejecutar DENTRO del TV box (Termux). Probado en ZTE B820C-A15 (Android 12).
#
#  Cómo funciona:
#    El servicio de sistema "adb" (IAdbManager) expone allowDebugging(bool, String)
#    como la transacción 1. Se invoca por `service call`, lo que registra
#    nuestra clave pública en la lista de claves autorizadas de adbd.
#    Después basta `adb connect 127.0.0.1:5555`.
#
#  Resultado: shell uid=2000(shell) y sobrevive a reinicios
#             (persist.sys.usb.config=adb -> adbd arranca solo).
# ============================================================================
export PATH=$PATH:/data/data/com.termux/files/usr/bin
set -u

KEY="${1:-$HOME/.android/adbkey.pub}"

echo "=== 0. clave de ADB ==="
if [ ! -f "$KEY" ]; then
  echo "[*] No hay clave en $KEY -> generando..."
  mkdir -p "$HOME/.android"
  if command -v adb >/dev/null 2>&1; then
    adb keygen "$HOME/.android/adbkey"
  else
    echo "[!] Falta 'adb'. Instálalo con: pkg install android-tools"
    exit 1
  fi
fi
chmod 600 "$HOME/.android/adbkey" 2>/dev/null
echo "    usando: $KEY"
head -c 40 "$KEY"; echo "..."

echo "=== 1. autorizar la clave (IAdbManager tx=1, alwaysAllow=true) ==="
PUB="$(cat "$KEY")"
service call adb 1 i32 1 s16 "$PUB" 2>&1 | head -3

echo "=== 2. activar adb por TCP y conectar ==="
setprop persist.sys.usb.config adb 2>/dev/null || true
sleep 3
adb connect 127.0.0.1:5555 2>&1 | tail -2
sleep 2
adb devices 2>&1 | tail -3

echo "=== 3. comprobar shell (debe salir uid=2000(shell)) ==="
adb -s 127.0.0.1:5555 shell 'id' </dev/null 2>&1 | tail -2

echo
echo "Notas:"
echo " - Si el paso 1 dice 'Result: Parcel(...)' suele estar bien: la clave queda registrada."
echo " - Si 'adb devices' sale 'unauthorized', repite el paso 1 y reconecta."
echo " - Tras un reinicio: basta 'adb connect 127.0.0.1:5555' (la clave ya está autorizada)."
