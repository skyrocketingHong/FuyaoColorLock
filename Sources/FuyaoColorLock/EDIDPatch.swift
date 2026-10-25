import Foundation

/// Removes only CTA-advertised YCbCr capability. It does not select RGB range,
/// bit depth, HDR, or an ICC profile, and does not install the generated data.
struct EDIDPatch {
    let originalData: Data
    let patchedData: Data
    let plistData: Data
    let vendorID: Int
    let productID: Int
    let removed420Blocks: Int
    let clearedCTAFlags: Int
    let patchedCTAExtensions: Int

    var vendorDirectoryName: String { "DisplayVendorID-\(String(vendorID, radix: 16))" }
    var productFileName: String { "DisplayProductID-\(String(productID, radix: 16))" }
    var hasChanges: Bool { originalData != patchedData }

    static func make(from data: Data) throws -> EDIDPatch {
        let original = [UInt8](data)
        try validate(original)
        var patched = original
        var foundCTA = false
        var removed420Blocks = 0
        var clearedCTAFlags = 0
        var patchedCTAExtensions = 0

        for index in 1..<(original.count / 128) {
            let start = index * 128
            guard original[start] == 0x02 else { continue }
            foundCTA = true
            var cta = Array(original[start..<(start + 128)])
            guard cta[1] == 3 else { throw EDIDPatchError.unsupportedCTARevision }
            let offset = Int(cta[2])
            guard offset == 0 || (4...127).contains(offset) else {
                throw EDIDPatchError.invalidTimingOffset
            }
            if offset == 0 && cta[4..<127].contains(where: { $0 != 0 }) {
                throw EDIDPatchError.dataWithoutOffset
            }

            var retained: [UInt8] = []
            var cursor = 4
            while cursor < offset {
                let header = cta[cursor]
                if header == 0 {
                    guard cta[cursor..<offset].allSatisfy({ $0 == 0 }) else {
                        throw EDIDPatchError.nonzeroPadding
                    }
                    retained.append(contentsOf: cta[cursor..<offset])
                    break
                }
                // CTA-861: 3-bit tag, 5-bit payload length; extended 0x0E and
                // 0x0F are Y420VDB and Y420CMDB. An empty CMDB means all SVDs.
                let tag = header >> 5
                let length = Int(header & 0x1F)
                let end = cursor + 1 + length
                guard end <= offset, tag != 7 || length > 0 else {
                    throw EDIDPatchError.truncatedDataBlock
                }
                if tag == 7 && (cta[cursor + 1] == 0x0E || cta[cursor + 1] == 0x0F) {
                    removed420Blocks += 1
                } else {
                    retained.append(contentsOf: cta[cursor..<end])
                }
                cursor = end
            }

            if offset != 0 {
                let newOffset = 4 + retained.count
                let tail = cta[offset..<127]
                let body = retained + tail + [UInt8](repeating: 0, count: offset - newOffset)
                cta.replaceSubrange(4..<127, with: body)
                cta[2] = UInt8(newOffset)
            }
            if cta[3] & 0x30 != 0 {
                cta[3] &= ~0x30
                clearedCTAFlags += 1
            }
            cta[127] = UInt8((256 - cta[..<127].reduce(0) { $0 + Int($1) } % 256) % 256)
            if !cta.elementsEqual(original[start..<(start + 128)]) {
                patchedCTAExtensions += 1
            }
            patched.replaceSubrange(start..<(start + 128), with: cta)
        }
        guard foundCTA else { throw EDIDPatchError.noCTAExtension }
        try validate(patched)
        let vendorID = Int(original[8]) << 8 | Int(original[9])
        let productID = Int(original[11]) << 8 | Int(original[10])
        let patchedData = Data(patched)
        let plist: [String: Any] = [
            "DisplayVendorID": vendorID,
            "DisplayProductID": productID,
            "IODisplayEDID": patchedData,
        ]
        return EDIDPatch(
            originalData: data,
            patchedData: patchedData,
            plistData: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
            vendorID: vendorID,
            productID: productID,
            removed420Blocks: removed420Blocks,
            clearedCTAFlags: clearedCTAFlags,
            patchedCTAExtensions: patchedCTAExtensions
        )
    }

    private static func validate(_ bytes: [UInt8]) throws {
        // ASVS 2.2.1/2.2.3: bounds, extension count, and checksums agree before editing.
        guard bytes.count >= 128, bytes.count.isMultiple(of: 128) else {
            throw EDIDPatchError.invalidLength
        }
        guard bytes.prefix(8).elementsEqual([0, 255, 255, 255, 255, 255, 255, 0]) else {
            throw EDIDPatchError.invalidHeader
        }
        guard bytes.count == (Int(bytes[126]) + 1) * 128 else {
            throw EDIDPatchError.extensionCountMismatch
        }
        for start in stride(from: 0, to: bytes.count, by: 128) {
            guard bytes[start..<(start + 128)].reduce(0, { $0 + Int($1) }) % 256 == 0 else {
                throw EDIDPatchError.invalidChecksum
            }
        }
    }
}

enum EDIDPatchError: LocalizedError, Equatable {
    case invalidLength
    case invalidHeader
    case extensionCountMismatch
    case invalidChecksum
    case unsupportedCTARevision
    case invalidTimingOffset
    case dataWithoutOffset
    case nonzeroPadding
    case truncatedDataBlock
    case noCTAExtension

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            return String(localized: "The EDID data is incomplete. No override was created.")
        case .invalidHeader:
            return String(localized: "The EDID header is invalid. No override was created.")
        case .extensionCountMismatch:
            return String(localized: "The EDID extension count does not match the available data.")
        case .invalidChecksum:
            return String(localized: "The EDID checksum is invalid. No override was created.")
        case .unsupportedCTARevision:
            return String(localized: "This EDID uses an unsupported CTA revision.")
        case .invalidTimingOffset:
            return String(localized: "The CTA timing offset is invalid. No override was created.")
        case .dataWithoutOffset:
            return String(localized: "The CTA data has no valid timing offset. No override was created.")
        case .nonzeroPadding:
            return String(localized: "The CTA padding contains unexpected data. No override was created.")
        case .truncatedDataBlock:
            return String(localized: "A CTA data block is truncated. No override was created.")
        case .noCTAExtension:
            return String(localized: "This display has no CTA extension that can be modified.")
        }
    }
}
