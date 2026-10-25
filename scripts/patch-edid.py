#!/usr/bin/env python3
"""Generate a display EDID override that removes CTA-advertised YCbCr modes.

Reads the live EDID from IORegistry, clears CTA 4:4:4 and 4:2:2 flags, removes
4:2:0 video/map blocks, and preserves all other extensions and timing data.
It does not set bit depth, range, HDR, or color gamut, and macOS may derive
additional capabilities elsewhere. Nothing is installed automatically.

Usage:
  python3 patch-edid.py --name "Redmi 27 NU" [--outdir edid-override]
"""

import argparse
import pathlib
import plistlib
import shlex
import subprocess
import sys

OVERRIDES_DIR = pathlib.Path("/Library/Displays/Contents/Resources/Overrides")


def read_registry_edid(name: str) -> tuple[bytes, int, int]:
    """Return (edid, productId, vendorId) for the display whose ProductName
    matches, as reported by the framebuffer Metadata dictionary."""
    # ASVS 1.2.5: no shell interpolation; decode typed plist data, not log text.
    result = subprocess.run(["ioreg", "-a", "-l", "-w", "0"],
                            capture_output=True, check=True, timeout=30)
    registry = plistlib.loads(result.stdout)
    candidates = set()
    pending = list(registry) if isinstance(registry, list) else [registry]
    while pending:
        node = pending.pop()
        if not isinstance(node, dict):
            continue
        metadata = node.get("Metadata")
        if isinstance(metadata, dict) and metadata.get("ProductName") == name:
            data = metadata.get("EDID")
            if isinstance(data, bytes):
                candidates.add(data)
        children = node.get("IORegistryEntryChildren", [])
        if isinstance(children, list):
            pending.extend(children)
    if not candidates:
        raise ValueError("No readable EDID matches the requested display name.")
    if len(candidates) != 1:
        raise ValueError("Multiple different EDIDs match this name; disconnect duplicates and retry.")
    edid = candidates.pop()
    validate_edid(edid)
    product_id = (edid[0x0B] << 8) | edid[0x0A]
    vendor_id = (edid[0x08] << 8) | edid[0x09]
    return edid, product_id, vendor_id


def validate_edid(edid: bytes) -> None:
    """Reject incomplete or corrupt input before producing an override."""
    # ASVS 2.2.1, 2.2.3: length, extension count, and checksums must agree.
    if len(edid) < 128 or len(edid) % 128:
        raise ValueError("EDID length must be a nonzero multiple of 128 bytes.")
    if edid[:8] != bytes.fromhex("00ffffffffffff00"):
        raise ValueError("Invalid EDID header.")
    if len(edid) != (edid[126] + 1) * 128:
        raise ValueError("EDID extension count does not match the available data.")
    for index in range(len(edid) // 128):
        if sum(edid[index * 128:(index + 1) * 128]) % 256:
            raise ValueError(f"Invalid checksum in EDID block {index}.")


def patch_cea(edid: bytes) -> tuple[bytes, list[str]]:
    """Patch every CTA extension, keeping unrelated blocks byte-for-byte."""
    validate_edid(edid)
    patched = bytearray(edid)
    changes: list[str] = []
    found_cta = False
    for index in range(1, len(edid) // 128):
        start = index * 128
        if edid[start] != 0x02:
            continue
        found_cta = True
        cea = bytearray(edid[start:start + 128])
        if cea[1] != 3:
            raise ValueError(f"Unsupported CTA revision {cea[1]} in block {index}; left unmodified.")
        offset = cea[2]
        if offset != 0 and not 4 <= offset <= 127:
            raise ValueError(f"Invalid CTA detailed-timing offset in block {index}.")
        if offset == 0 and any(cea[4:127]):
            raise ValueError(f"CTA block {index} has data but no data/timing offset.")

        retained = bytearray()
        cursor = 4
        while cursor < offset:
            header = cea[cursor]
            if header == 0:
                if any(cea[cursor:offset]):
                    raise ValueError(f"Nonzero data follows CTA padding in block {index}.")
                retained.extend(cea[cursor:offset])
                break
            # CTA-861 data blocks use a 3-bit tag and a 5-bit payload length.
            # Reference: edid-decode parse-cta-block.cpp, cta_block/cta_ext_block.
            tag, length = header >> 5, header & 0x1F
            end = cursor + 1 + length
            if end > offset or (tag == 7 and length == 0):
                raise ValueError(f"Truncated CTA data block at byte {start + cursor}.")
            payload = cea[cursor + 1:end]
            if tag == 7 and payload[0] in (0x0E, 0x0F):
                changes.append(f"CTA block {index}: removed YCbCr 4:2:0 extended block 0x{payload[0]:02X}")
            else:
                retained.extend(cea[cursor:end])
                if ((tag == 3 and payload[:3] == b"\xd8\x5d\xc4")
                        or (tag == 7 and payload[0] == 0x79)):
                    changes.append(f"NOTE: CTA block {index} HDMI Forum capabilities remain unchanged.")
            cursor = end

        if offset:
            new_offset = 4 + len(retained)
            tail = cea[offset:127]
            cea[4:127] = retained + tail + bytes(offset - new_offset)
            cea[2] = new_offset
        if cea[3] & 0x30:
            cea[3] &= ~0x30
            changes.append(f"CTA block {index}: cleared YCbCr 4:4:4 and 4:2:2 capability flags")
        cea[127] = (-sum(cea[:127])) & 0xFF
        patched[start:start + 128] = cea
    if not found_cta:
        raise ValueError("EDID contains no supported CTA extension to patch.")
    validate_edid(patched)
    return bytes(patched), changes


def build_plist(product_id: int, vendor_id: int, edid: bytes) -> str:
    validate_edid(edid)
    return plistlib.dumps({"DisplayProductID": product_id,
                          "DisplayVendorID": vendor_id,
                          "IODisplayEDID": edid}, fmt=plistlib.FMT_XML).decode()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="display ProductName from IORegistry")
    parser.add_argument("--outdir", default="edid-override", help="where to write the override")
    args = parser.parse_args()

    try:
        edid, product_id, vendor_id = read_registry_edid(args.name)
        patched, changes = patch_cea(edid)
    except (ValueError, plistlib.InvalidFileException, subprocess.SubprocessError, OSError) as error:
        sys.exit(f"Cannot generate override: {error}")
    print(f"{args.name}: DisplayVendorID {vendor_id}, DisplayProductID {product_id}, "
          f"EDID {len(edid)} bytes, {edid[126]} extension block(s)")

    if patched == edid:
        print("Nothing to patch: no YCbCr capability bits found.")
        return
    for change in changes:
        print("  " + change)
    print("All extension blocks preserved; modified CTA checksums updated.")
    print("This does not enforce bit depth, range, HDR, or gamut. Verify available modes after installation.")

    outdir = pathlib.Path(args.outdir)
    # Apple IODisplayLib.c resolves override names using hexadecimal %x.
    target_dir = outdir / f"DisplayVendorID-{vendor_id:x}"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"DisplayProductID-{product_id:x}"
    content = build_plist(product_id, vendor_id, patched)
    if target.exists() and target.read_text() != content:
        sys.exit("Output already contains a different override; use another --outdir to preserve it.")
    target.write_text(content)
    print(f"\nOverride written: {target}\n")

    dest_dir = OVERRIDES_DIR / target_dir.name
    dest = dest_dir / target.name
    quote = lambda path: shlex.quote(str(path))
    # ASVS 1.2.5: printed copy commands also require shell-safe path quoting.
    print("If an override already exists at the destination, back it up before replacing it.")
    print("Install (then unplug/replug the display, or reboot):")
    print(f"  sudo mkdir -p {quote(dest_dir)}")
    print(f"  sudo cp -i {quote(target.resolve())} {quote(dest)}")
    print("\nRollback: restore your previous override, or remove this file only if newly installed:")
    print(f"  sudo rm -i {quote(dest)}")
    print("Then unplug/replug the display.")


if __name__ == "__main__":
    main()
