#!/usr/bin/env python3
"""
runsys.py — ejecuta un script/comando en la caja como **uid=1000 (system_app)**
usando el endpoint /RunCmd de la app de fábrica.

Uso:
    python3 runsys.py "id; getprop ro.build.version.release"
    python3 runsys.py -f mi_script.sh          # ejecuta el contenido de un archivo

Se puede lanzar:
  * desde tu PC, si tienes acceso al puerto 10001 (p. ej. por un túnel SSH a
    Termux con -L 10001:127.0.0.1:10001), o
  * dentro del propio Termux del TV box (recomendado).

Antes hay que "rearmar" el canal: scripts/rearm.sh
"""
import json
import sys
import urllib.request

URL = "http://127.0.0.1:10001/RunCmd"


def run(cmd: str, timeout: int = 120) -> str:
    body = json.dumps({"dictData": {"shellCmd": cmd, "requestRst": "true"}}).encode()
    req = urllib.request.Request(URL, data=body,
                                headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    return data.get("dictData", {}).get("shellCmdRst", "(sin salida)")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    if sys.argv[1] == "-f":
        cmd = open(sys.argv[2], "r").read()
    else:
        cmd = sys.argv[1]
    try:
        print(run(cmd))
    except Exception as e:                      # noqa: BLE001
        print(f"[!] Error: {e}", file=sys.stderr)
        print("    ¿Está rearmado el canal? -> scripts/rearm.sh", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
