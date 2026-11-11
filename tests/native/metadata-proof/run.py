#!/usr/bin/env python3
"""Build/run synthetic native metadata probes on an owned disposable APFS image."""
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/metadata-proof"


def checked(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    binary = OUT / "metadata-proof"
    checked(["swiftc", "-target", f"{platform.machine()}-apple-macos14.0",
             "-module-cache-path", OUT / "ModuleCache", Path(__file__).with_name("main.swift"), "-o", binary])
    owned = Path(tempfile.mkdtemp(prefix="run-", dir=OUT))
    mount = owned / "mounted"
    mount.mkdir()
    image = owned / "fixture.dmg"
    attached = False
    attachment_attempted = False
    cleaned = False
    report = None
    try:
        checked(["hdiutil", "create", "-size", "64m", "-fs", "APFS", "-volname",
                 "FolderMasterMetadataProof", "-type", "UDIF", image], stdout=subprocess.PIPE)
        attachment_attempted = True
        attachment = checked(["hdiutil", "attach", image, "-mountpoint", mount, "-nobrowse",
                              "-noautoopen", "-plist"], stdout=subprocess.PIPE)
        attached = True
        entities = plistlib.loads(attachment.stdout)["system-entities"]
        if not any(entity.get("mount-point") == str(mount) for entity in entities):
            raise RuntimeError("Image attachment did not report the requested owned mount point")
        result = checked([binary, owned, mount], stdout=subprocess.PIPE)
        report = json.loads(result.stdout)
        report["architecture"] = platform.machine()
        report["deploymentTarget"] = "macOS 14.0 (compile only)"
    finally:
        if attached or os.path.ismount(mount):
            # Never detach by a guessed/shared device number; only our owned mount.
            checked(["hdiutil", "detach", mount], stdout=subprocess.PIPE)
        if attachment_attempted and not attached and not os.path.ismount(mount):
            # A failed attachment can leave an unmounted device. Preserve our image
            # for inspection rather than guessing a device identifier or unlinking it.
            print(f"Attachment state uncertain; owned image retained at {owned}")
        elif not os.path.ismount(mount):
            shutil.rmtree(owned)
            cleaned = True
    report["ownedImageDetachedAndRemoved"] = cleaned
    destination = OUT / "latest.json"
    destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"PASS: {len(report['copies'])} fixture copy probes; quarantine retained, OS may rewrite its bytes")
    print("Tag/label transitions recorded on two distinct local volumes")
    print(f"Owned image detached and removed: {cleaned}")
    print(f"Evidence: {destination}")


if __name__ == "__main__":
    main()
