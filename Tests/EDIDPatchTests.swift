import Foundation

@main
struct EDIDPatchTests {
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            try fixtureParityIfRequested()
            return
        }
        try removes420AndPreservesTimings()
        try preservesEveryExtension()
        try rejectsMalformedInput()
        try noChangeIsExplicit()
        try createsValidOverridePropertyList()
        print("Passed 5 Swift EDID regression groups.")
    }

    private static func removes420AndPreservesTimings() throws {
        let video: [UInt8] = [0x4A] + Array(1...10)
        let colorimetry: [UInt8] = [0xE3, 5, 0xC0, 0]
        let blocks = video + [0xE3, 0x0E, 96, 97, 0xE1, 0x0F] + colorimetry
        let dtd: [UInt8] = [2, 0x3A] + Array(2...17)
        let original = edid([cta(blocks: blocks, dtd: dtd)])
        let patch = try EDIDPatch.make(from: original)
        let output = [UInt8](patch.patchedData)
        let expected = video + colorimetry
        try expect(patch.originalData == original, "Original EDID must remain available")
        try expect(patch.removed420Blocks == 2 && patch.clearedCTAFlags == 1, "Both Y420 data blocks must be removed")
        try expect(patch.patchedCTAExtensions == 1 && patch.hasChanges, "Changed block count must be explicit")
        try expect(output[130] == 4 + expected.count, "Detailed timing offset must follow retained blocks")
        try expect(Array(output[132..<(132 + expected.count)]) == expected, "Non-YCbCr blocks must be preserved")
        let timingStart = 128 + Int(output[130])
        try expect(Array(output[timingStart..<(timingStart + 18)]) == dtd, "Detailed timing bytes must not change")
        try expect(output[131] & 0x30 == 0, "CTA YCbCr flags must be cleared")
        try expect(try EDIDPatch.make(from: patch.patchedData).hasChanges == false, "Patching twice must be idempotent")
    }

    private static func preservesEveryExtension() throws {
        var other = [UInt8](repeating: 0, count: 128)
        other[0] = 0x70
        other[1] = 0x20
        other = checksum(other)
        let original = edid([other, cta(blocks: [0xE2, 0x0F, 1]), cta()])
        let patch = try EDIDPatch.make(from: original)
        try expect(patch.patchedData.count == original.count, "No extension may be truncated")
        try expect(Array(patch.patchedData[128..<256]) == other, "Non-CTA extension must be preserved")
        try expect(patch.patchedData[126] == 3, "Extension count must be preserved")
        try expect(patch.patchedCTAExtensions == 2, "Every CTA extension must be patched")
        let bytes = [UInt8](patch.patchedData)
        for start in stride(from: 0, to: bytes.count, by: 128) {
            try expect(bytes[start..<(start + 128)].reduce(0) { $0 + Int($1) } % 256 == 0, "Every block checksum must remain valid")
        }
    }

    private static func rejectsMalformedInput() throws {
        let valid = edid([cta()])
        try expectError(.invalidLength, data: Data())
        try expectError(.invalidLength, data: valid.dropLast())
        var bytes = [UInt8](valid)
        bytes[0] = 1
        try expectError(.invalidHeader, data: Data(bytes))
        bytes = [UInt8](valid)
        bytes[126] = 2
        try expectError(.extensionCountMismatch, data: Data(bytes))
        bytes = [UInt8](valid)
        bytes[140] ^= 1
        try expectError(.invalidChecksum, data: Data(bytes))
        try expectError(.noCTAExtension, data: edid([]))

        for (header, offset): (UInt8, UInt8) in [(0xE5, 6), (0xE0, 5), (0x41, 2), (0x41, 128)] {
            var block = cta()
            block[2] = offset
            block[4] = header
            try expectError(offset < 4 || offset > 127 ? .invalidTimingOffset : .truncatedDataBlock,
                            data: edid([checksum(block)]))
        }
        var block = cta()
        block[1] = 2
        try expectError(.unsupportedCTARevision, data: edid([checksum(block)]))
        block = cta()
        block[2] = 0
        block[4] = 1
        try expectError(.dataWithoutOffset, data: edid([checksum(block)]))
    }

    private static func noChangeIsExplicit() throws {
        var empty = [UInt8](repeating: 0, count: 128)
        empty[0] = 2
        empty[1] = 3
        for block in [checksum(empty), cta(blocks: [0x41, 16], flags: 0)] {
            let original = edid([block])
            let patch = try EDIDPatch.make(from: original)
            try expect(!patch.hasChanges && patch.patchedCTAExtensions == 0, "Already constrained EDID must report no change")
            try expect(patch.patchedData == original, "Unchanged EDID must stay byte-for-byte equal")
        }
    }

    private static func createsValidOverridePropertyList() throws {
        let patch = try EDIDPatch.make(from: edid([cta()]))
        guard let plist = try PropertyListSerialization.propertyList(from: patch.plistData, format: nil) as? [String: Any] else {
            throw Failure(message: "Override plist cannot be decoded")
        }
        try expect(patch.vendorDirectoryName == "DisplayVendorID-10ac", "Vendor path must use hexadecimal")
        try expect(patch.productFileName == "DisplayProductID-1234", "Product path must use hexadecimal")
        try expect(plist["DisplayVendorID"] as? Int == 0x10AC, "Plist vendor ID must stay numeric")
        try expect(plist["DisplayProductID"] as? Int == 0x1234, "Plist product ID must stay numeric")
        try expect(plist["IODisplayEDID"] as? Data == patch.patchedData, "Plist EDID must be binary data")
    }

    private static func fixtureParityIfRequested() throws {
        guard CommandLine.arguments.count == 3 else { return }
        let patch = try EDIDPatch.make(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        try patch.patchedData.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }

    private static func checksum(_ bytes: [UInt8]) -> [UInt8] {
        var output = bytes
        output[127] = UInt8((256 - output[..<127].reduce(0) { $0 + Int($1) } % 256) % 256)
        return output
    }

    private static func edid(_ extensions: [[UInt8]]) -> Data {
        var base = [UInt8](repeating: 0, count: 128)
        base.replaceSubrange(0..<8, with: [0, 255, 255, 255, 255, 255, 255, 0])
        base.replaceSubrange(8..<12, with: [0x10, 0xAC, 0x34, 0x12])
        base[18] = 1
        base[19] = 4
        base[126] = UInt8(extensions.count)
        return Data(checksum(base) + extensions.flatMap { $0 })
    }

    private static func cta(blocks: [UInt8] = [], dtd: [UInt8] = [], flags: UInt8 = 0x30) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 128)
        output.replaceSubrange(0..<4, with: [2, 3, UInt8(4 + blocks.count), flags])
        output.replaceSubrange(4..<(4 + blocks.count), with: blocks)
        output.replaceSubrange((4 + blocks.count)..<(4 + blocks.count + dtd.count), with: dtd)
        return checksum(output)
    }

    private static func expectError(_ expected: EDIDPatchError, data: Data) throws {
        do {
            _ = try EDIDPatch.make(from: data)
            throw Failure(message: "Expected rejection: \(expected)")
        } catch let error as EDIDPatchError {
            try expect(error == expected, "Wrong EDID error: \(error)")
        }
    }

    private struct Failure: Error { let message: String }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
