#!/usr/bin/env python3
"""Generate a display EDID override that strips YCbCr support from an external
display, so macOS only offers RGB connection modes.

Reads the live EDID from IORegistry, clears the CEA-861 YCbCr capability bits
(4:4:4 / 4:2:2 flags and the YCbCr 4:2:0 capability map block), fixes the
checksums, and writes an override plist plus the exact install/uninstall
commands. Nothing is installed unless you run the printed sudo command.

Usage:
  python3 patch-edid.py --name "Redmi 27 NU" [--outdir edid-override]
"""

import argparse
import base64
import pathlib
import re
import subprocess
import sys

OVERRIDES_DIR = pathlib.Path("/Library/Displays/Contents/Resources/Overrides")


def read_registry_edid(name: str) -> tuple[bytes, int, int]:
    """Return (edid, productId, vendorId) for the display whose ProductName
    matches, as reported by the framebuffer Metadata dictionary."""
    out = subprocess.run(["ioreg", "-l", "-w", "0"], capture_output=True, text=True).stdout
    pattern = re.compile(
        r'"Metadata" = \{[^{}]*?"EDID"=<([0-9a-fA-F]+)>[^{}]*?"ProductName"="([^"]+)"[^{}]*?\}'
    )
    # The metadata dictionary appears twice per display (parent+child); either is fine.
    seen = {}
    for m in pattern.finditer(out):
        seen[m.group(2)] = m.group(1)
    if name not in seen:
        available = ", ".join(sorted(seen)) or "none"
        sys.exit(f"Display {name!r} not found in IORegistry (available: {available})")
    edid = bytes.fromhex(seen[name])
    if len(edid) < 256:
        sys.exit(f"Unexpected EDID length {len(edid)} (need base block + CEA extension)")
    if edid[126] == 0:
        sys.exit("EDID has no extension blocks; this display does not advertise YCbCr via CEA.")
    if edid[128] != 0x02:
        sys.exit("First extension block is not CEA-861; aborting.")
    product_id = (edid[0x0B] << 8) | edid[0x0A]
    vendor_id = (edid[0x08] << 8) | edid[0x09]
    return edid, product_id, vendor_id


def patch_cea(edid: bytes) -> tuple[bytes, list[str]]:
    """Clear YCbCr capability in the CEA-861 extension block (bytes 128..255)."""
    cea = bytearray(edid[128:256])
    changes: list[str] = []

    flags = cea[3]
    y444, y422 = flags & 0x20, flags & 0x10
    if y444 or y422:
        cea[3] = flags & ~0x30
        changes.append(
            f"capability flags 0x{flags:02X} -> 0x{cea[3]:02X} "
            f"(cleared YCbCr 4:4:4={'yes' if y444 else 'no'}, 4:2:2={'yes' if y422 else 'no'})"
        )

    # Walk CTA data blocks between byte 4 and the DTD offset.
    dtd_offset = cea[2]
    i = 4
    while i < dtd_offset:
        tag_len = cea[i]
        tag, length = tag_len >> 3, tag_len & 0x07
        if tag == 0 or i + 1 + length > dtd_offset:
            break
        if tag == 15:  # YCbCr 4:2:0 Capability Map: zero the bitmap.
            for k in range(1, 1 + length):
                cea[i + k] = 0
            changes.append(
                f"YCbCr 4:2:0 capability map block at byte {128 + i}: bitmap zeroed"
            )
        if tag == 7:  # extended block: mention video capability blocks only.
            sub = cea[i + 1]
            if sub == 5:
                changes.append(
                    f"note: Video Capability Data Block present at byte {128 + i} (left untouched)"
                )
        i += 1 + length

    # HDMI 2.0 4:2:0 depth flags live in an SCDB/HF-VSDB; warn if present.
    if b"\xc4\x5d\xd8" in bytes(cea):
        changes.append(
            "WARNING: HDMI Forum VSDB (SCDB) present - its 4:2:0 depth bits were NOT patched; "
            "re-check available modes after installing."
        )

    cea[127] = (-sum(cea[:127])) & 0xFF  # CEA checksum
    return bytes(edid[:128]) + bytes(cea), changes


def build_plist(product_id: int, vendor_id: int, edid: bytes) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        "<plist version=\"1.0\">\n<dict>\n"
        f"\t<key>DisplayProductID</key>\n\t<integer>{product_id}</integer>\n"
        f"\t<key>DisplayVendorID</key>\n\t<integer>{vendor_id}</integer>\n"
        f"\t<key>IODisplayEDID</key>\n\t<data>{base64.b64encode(edid).decode()}</data>\n"
        "</dict>\n</plist>\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="display ProductName from IORegistry")
    parser.add_argument("--outdir", default="edid-override", help="where to write the override")
    args = parser.parse_args()

    edid, product_id, vendor_id = read_registry_edid(args.name)
    print(f"{args.name}: DisplayVendorID {vendor_id}, DisplayProductID {product_id}, "
          f"EDID {len(edid)} bytes, {edid[126]} extension block(s)")

    patched, changes = patch_cea(edid)
    if patched == edid:
        print("Nothing to patch: no YCbCr capability bits found.")
        return
    for change in changes:
        print("  " + change)
    print(f"CEA checksum updated: 0x{edid[255]:02X} -> 0x{patched[255]:02X}")

    outdir = pathlib.Path(args.outdir)
    target_dir = outdir / f"DisplayVendorID-{vendor_id}"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"DisplayProductID-{product_id}"
    target.write_text(build_plist(product_id, vendor_id, patched))
    print(f"\nOverride written: {target}\n")

    dest_dir = OVERRIDES_DIR / f"DisplayVendorID-{vendor_id}"
    print("Install (then unplug/replug the display, or reboot):")
    print(f'  sudo mkdir -p "{dest_dir}"')
    print(f'  sudo cp "{target.resolve()}" "{dest_dir}/DisplayProductID-{product_id}"')
    print("\nUninstall (then unplug/replug the display):")
    print(f'  sudo rm "{dest_dir}/DisplayProductID-{product_id}"')


if __name__ == "__main__":
    main()
