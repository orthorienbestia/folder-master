#!/usr/bin/env python3
"""Launch only the signed synthetic OCR proof, with a reachable local control."""
from pathlib import Path
import socket
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: run-ocr-proof.py OCRProof.app")
app = Path(sys.argv[1]).resolve()
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.bind(("127.0.0.1", 0))
    listener.listen(4)
    address = listener.getsockname()
    with socket.create_connection(address, timeout=2):
        accepted, _ = listener.accept()
        accepted.close()
    result = subprocess.run([str(app / "Contents/MacOS/OCRProofHost"), str(address[1])], timeout=180)
    raise SystemExit(result.returncode)
