"""Offline EDID regressions; fixtures contain no physical display data."""

import importlib.util
import contextlib
import io
import pathlib
import plistlib
import shlex
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "patch-edid.py"
SPEC = importlib.util.spec_from_file_location("patch_edid", SCRIPT)
patcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patcher)


def checksum(block):
    block = bytearray(block)
    block[127] = (-sum(block[:127])) & 0xFF
    return bytes(block)


def edid(*extensions):
    base = bytearray(128)
    base[:8] = bytes.fromhex("00ffffffffffff00")
    base[8:12] = bytes.fromhex("10ac3412")
    base[18:20] = bytes([1, 4])
    base[126] = len(extensions)
    return checksum(base) + b"".join(extensions)


def cta(blocks=b"", dtd=b"", flags=0x30):
    block = bytearray(128)
    block[:4] = bytes([2, 3, 4 + len(blocks), flags])
    block[4:4 + len(blocks)] = blocks
    block[4 + len(blocks):4 + len(blocks) + len(dtd)] = dtd
    return checksum(block)


class PatchEDIDTests(unittest.TestCase):
    def test_removes_y420_blocks_and_preserves_long_blocks_and_dtd(self):
        # A 10-byte video block catches the old three-bit length parser.
        video = bytes([0x4A]) + bytes(range(1, 11))
        y420_video = bytes([0xE3, 0x0E, 96, 97])
        # A tag-only CMDB means all regular SVDs support 4:2:0; remove it.
        y420_map = bytes([0xE1, 0x0F])
        colorimetry = bytes([0xE3, 0x05, 0xC0, 0])
        dtd = bytes([0x02, 0x3A]) + bytes(range(2, 18))
        original = edid(cta(video + y420_video + y420_map + colorimetry, dtd))

        patched, _ = patcher.patch_cea(original)
        expected = video + colorimetry
        self.assertEqual(patched[131] & 0x30, 0)
        self.assertEqual(patched[130], 4 + len(expected))
        self.assertEqual(patched[132:132 + len(expected)], expected)
        self.assertEqual(patched[128 + patched[130]:146 + patched[130]], dtd)
        self.assertEqual(patched[:128], original[:128])
        self.assertEqual(sum(patched[128:256]) % 256, 0)
        self.assertEqual(patcher.patch_cea(patched)[0], patched)

    def test_preserves_all_extensions_and_patches_each_cta(self):
        other = bytearray(128)
        other[:5] = bytes([0x70, 0x20, 0, 0, 0])
        other = checksum(other)
        original = edid(other, cta(bytes([0xE2, 0x0F, 0x01])), cta())
        patched, _ = patcher.patch_cea(original)
        self.assertEqual(len(patched), len(original))
        self.assertEqual(patched[126], 3)
        self.assertEqual(patched[128:256], other)
        self.assertEqual(patched[259] & 0x30, 0)
        self.assertEqual(patched[387] & 0x30, 0)
        self.assertTrue(all(sum(patched[i:i + 128]) % 256 == 0
                            for i in range(0, len(patched), 128)))

    def test_rejects_missing_damaged_or_inconsistent_edid(self):
        valid = edid(cta())
        bad_header = bytearray(valid)
        bad_header[0] = 1
        bad_checksum = bytearray(valid)
        bad_checksum[140] ^= 1
        bad_count = bytearray(valid)
        bad_count[126] = 2
        bad_count[:128] = checksum(bad_count[:128])
        for data in [b"", valid[:-1], bytes(bad_header), bytes(bad_checksum),
                     bytes(bad_count), edid()]:
            with self.subTest(length=len(data)):
                with self.assertRaises(ValueError):
                    patcher.patch_cea(data)

    def test_rejects_truncated_or_invalid_cta_blocks(self):
        for header, offset in [(0xE5, 6), (0xE0, 5), (0x41, 2), (0x41, 128)]:
            block = bytearray(cta())
            block[2] = offset
            block[4] = header
            with self.subTest(header=header, offset=offset):
                with self.assertRaises(ValueError):
                    patcher.patch_cea(edid(checksum(block)))

    def test_empty_cta_and_non_ycbcr_edid_are_unchanged(self):
        empty = bytearray(128)
        empty[:4] = bytes([2, 3, 0, 0])
        for extension in [checksum(empty), cta(bytes([0x41, 16]), flags=0)]:
            original = edid(extension)
            self.assertEqual(patcher.patch_cea(original)[0], original)

    def test_plist_contains_binary_edid_and_numeric_identifiers(self):
        patched, _ = patcher.patch_cea(edid(cta()))
        xml = patcher.build_plist(0x1234, 0x10AC, patched)
        plist = plistlib.loads(xml.encode())
        self.assertEqual(plist["IODisplayEDID"], patched)
        self.assertEqual(plist["DisplayVendorID"], 0x10AC)
        self.assertEqual(plist["DisplayProductID"], 0x1234)
        self.assertIn("<data>", xml)

    def test_registry_uses_typed_data_and_rejects_ambiguous_names(self):
        data = edid(cta())
        node = {"Metadata": {"ProductName": "Test Panel", "EDID": data}}
        registry = [{"IORegistryEntryChildren": [node, node]}]
        result = subprocess.CompletedProcess([], 0, plistlib.dumps(registry))
        with mock.patch.object(patcher.subprocess, "run", return_value=result):
            self.assertEqual(patcher.read_registry_edid("Test Panel"), (data, 0x1234, 0x10AC))
        different = {"Metadata": {"ProductName": "Test Panel", "EDID": edid(cta(flags=0))}}
        result.stdout = plistlib.dumps([node, different])
        with mock.patch.object(patcher.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "Multiple different"):
                patcher.read_registry_edid("Test Panel")
            with self.assertRaisesRegex(ValueError, "No readable EDID"):
                patcher.read_registry_edid("Missing")

    def test_cli_writes_hex_paths_and_shell_safe_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = pathlib.Path(temporary) / "override with '$() ` chars"
            arguments = [str(SCRIPT), "--name", "Test Panel", "--outdir", str(output)]
            stream = io.StringIO()
            with mock.patch.object(patcher.sys, "argv", arguments), \
                    mock.patch.object(patcher, "read_registry_edid",
                                      return_value=(edid(cta()), 0x1234, 0x10AC)), \
                    contextlib.redirect_stdout(stream):
                patcher.main()
            target = output / "DisplayVendorID-10ac" / "DisplayProductID-1234"
            self.assertTrue(target.is_file())
            install = next(line for line in stream.getvalue().splitlines()
                           if line.startswith("  sudo cp"))
            self.assertEqual(shlex.split(install)[3], str(target.resolve()))
            self.assertEqual(pathlib.Path(shlex.split(install)[4]).name, "DisplayProductID-1234")


if __name__ == "__main__":
    unittest.main()
