import Foundation

@main
struct DisplayModelTests {
    private static let rgb = mode()
    private static let link = LinkDescription(range: 1, bitDepth: 8, eotf: 0, pixelEncoding: 0)

    static func main() throws {
        try missingTimingIsUnknown()
        try ambiguousRecordsAreNotCurrent()
        try incompleteRecordsStayUnknown()
        try colorimetryCannotBeInferredFromLink()
        try allTimingsDeduplicateByFormat()
        try legacyTargetCanBeCleared()
        try incompleteDriverModesAreNotInvented()
        try edidMatchingRejectsAmbiguity()
        print("Passed 8 display model regressions.")
    }

    private static func missingTimingIsUnknown() throws {
        for missingID: Int? in [nil, 999] {
            let value = display(timingID: missingID)
            try expect(value.currentTiming == nil, "Unknown timing must not select the highest scoring timing")
            try expect(value.currentModes.isEmpty, "Unknown timing must not advertise modes as currently active")
            try expect(!value.timings.isEmpty, "The supported timing table must remain available")
        }
    }

    private static func ambiguousRecordsAreNotCurrent() throws {
        let a = plist([linkDictionary()])
        let b = plist([linkDictionary(depth: 10)])
        for input in [[a, b], [b, a]] {
            try expect(WindowServerLinkModes.parse(input)["FIXTURE"] == .conflicting,
                       "Historical record order must not decide the active format")
        }
        try expect(WindowServerLinkModes.parse([a, a])["FIXTURE"] == .recorded(link),
                   "Identical historical records are unambiguous")
    }

    private static func incompleteRecordsStayUnknown() throws {
        var partial = linkDictionary()
        partial.removeValue(forKey: "BitDepth")
        let result = WindowServerLinkModes.parse([plist([linkDictionary(), partial])])
        try expect(result["FIXTURE"] == .unavailable, "Missing bit depth must not be invented as 8-bit")
        let unknown = LinkDescription(range: 7, bitDepth: 12, eotf: 9, pixelEncoding: 4)
        try expect(unknown.title.contains("EOTF 9") && unknown.title.contains("Range 7"),
                   "Unknown enum values must not be labeled SDR or Limited")
    }

    private static func colorimetryCannotBeInferredFromLink() throws {
        let p3 = mode(id: 3, colorimetry: 9)
        let srgb = mode(id: 4, colorimetry: 10)
        let value = display(modes: [p3, srgb], record: .recorded(link))
        try expect(value.configuredModeEntry == nil,
                   "A four-field link record cannot identify P3 versus sRGB")
    }

    private static func allTimingsDeduplicateByFormat() throws {
        let reassigned = mode(id: 53)
        let value = display(modes: [rgb, reassigned, mode(id: 54, colorimetry: 9)], timingID: nil)
        try expect(value.allSupportedModes.count == 2, "Mode IDs must not duplicate identical formats")
        try expect(value.allSupportedModes.contains(where: { $0.colorimetry == 9 }),
                   "Distinct raw colorimetry must remain a separate format")
        try expect(value.currentModes.isEmpty, "All-timing capabilities must not become the active table")
        try expect(mode(colorimetry: 9).colorimetryName == "Colorimetry 9",
                   "Unverified private colorimetry values must not be labeled as P3")
    }

    private static func legacyTargetCanBeCleared() throws {
        let suite = "FuyaoColorLock.Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(message: "Cannot create test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = display()
        defaults.set(rgb.id, forKey: "lock.\(value.legacySettingsID).targetModeID")
        defaults.set(true, forKey: "lock.\(value.legacySettingsID).enabled")
        let legacy = Settings.preference(for: value, defaults: defaults)
        try expect(legacy.legacyTargetID == rgb.id, "Legacy target ID should remain inspectable without interpretation")
        Settings.clearTarget(for: value, defaults: defaults)
        try expect(Settings.preference(for: value, defaults: defaults).legacyTargetID == nil,
                   "Clearing a historical target must remove it")
        try expect(defaults.object(forKey: "lock.\(value.legacySettingsID).enabled") == nil,
                   "Clearing must also remove the obsolete lock flag")
    }

    private static func incompleteDriverModesAreNotInvented() throws {
        let incomplete: [String: Any] = ["ID": 2, "Depth": 8]
        let raw: [[String: Any]] = [[
            "ID": 1, "HorizontalAttributes": ["Active": 1920],
            "VerticalAttributes": ["Active": 1080, "PreciseSyncRate": 3932160],
            "ColorModes": [incomplete],
        ]]
        try expect(DisplayCatalog.parseTimings(raw) == nil,
                   "Incomplete driver mode must not become an invented RGB/SDR option")
    }

    private static func edidMatchingRejectsAmbiguity() throws {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes.replaceSubrange(0..<8, with: [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        bytes[8] = 0x12
        bytes[9] = 0x34
        bytes[10] = 0x78
        bytes[11] = 0x56
        bytes[12] = 42
        let data = Data(bytes)
        try expect(DisplayCatalog.matchingEDID(vendor: 0x1234, product: 0x5678, serial: 42,
                                               candidates: [data]) == data,
                   "Hardware identity must decode EDID byte ordering")
        try expect(DisplayCatalog.matchingEDID(vendor: 0x1234, product: 0x5678, serial: 43,
                                               candidates: [data]) == nil,
                   "Different serials must not match by model alone")
        try expect(DisplayCatalog.matchingEDID(vendor: 0x1234, product: 0x5678, serial: 42,
                                               candidates: [data, data]) == nil,
                   "Repeated hardware identities must not pick an arbitrary transport")
        try expect(DisplayCatalog.matchingEDID(vendor: 0x1234, product: 0x5678, serial: 42,
                                               candidates: [Data([1, 2, 3])]) == nil,
                   "Incomplete EDID must not be used as an identity")
    }

    private static func mode(id: Int = 2, depth: Int = 8, colorimetry: Int = 0) -> ColorModeEntry {
        ColorModeEntry(timingID: 1, modeID: id, pixelEncoding: 0, depth: depth,
                       dynamicRange: 1, eotf: 0, colorimetry: colorimetry, score: 100)
    }

    private static func display(modes: [ColorModeEntry] = [rgb], timingID: Int? = 1,
                                record: RecordedLinkState = .unavailable) -> PhysicalDisplay {
        let timing = DisplayTiming(id: 1, width: 1920, height: 1080, refreshRateHz: 59.94, modes: modes)
        return PhysicalDisplay(id: "fixture", name: "Fixture", cgDirectDisplayID: 1,
                               uuidString: nil, timings: [timing], currentTimingID: timingID,
                               recordedLinkState: record, edid: nil, liveConnection: nil)
    }

    private static func linkDictionary(depth: Int = 8) -> [String: Any] {
        ["Range": 1, "BitDepth": depth, "EOTF": 0, "PixelEncoding": 0]
    }

    private static func plist(_ links: [[String: Any]]) -> [String: Any] {
        ["DisplaySets": ["Configs": links.map { ["DisplayConfig": [["UUID": "fixture", "LinkDescription": $0]]] }]]
    }

    private struct Failure: Error { let message: String }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
