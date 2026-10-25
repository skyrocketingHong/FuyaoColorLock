import CoreGraphics
import Foundation
import IOKit

/// A single connection color mode entry as published by the display driver
/// in IORegistry (`TimingElements → ColorModes`).
struct ColorModeEntry: Identifiable, Hashable {
    let timingID: Int
    let modeID: Int
    let pixelEncoding: Int
    let depth: Int
    let dynamicRange: Int
    let eotf: Int
    let colorimetry: Int
    let score: Int

    var id: String { "\(timingID)-\(modeID)" }

    /// Pixel encoding values verified against BetterDisplay's list on macOS 27:
    /// 0=RGB, 2=YCbCr 4:2:0, 3=YCbCr 4:4:4, 6=YCbCr 4:2:2.
    var encodingName: String {
        switch pixelEncoding {
        case 0: return "RGB"
        case 2: return "YCbCr 4:2:0"
        case 3: return "YCbCr 4:4:4"
        case 6: return "YCbCr 4:2:2"
        default: return "Encoding \(pixelEncoding)"
        }
    }

    var rangeName: String {
        switch dynamicRange {
        case 1: return "Full"
        case 0: return "Limited"
        default: return "Range \(dynamicRange)"
        }
    }

    var transferName: String {
        switch eotf {
        case 0: return "SDR"
        case 1: return "HDR"
        case 2: return "HDR10"
        default: return "EOTF \(eotf)"
        }
    }

    var colorimetryName: String {
        "Colorimetry \(colorimetry)"
    }

    /// Menu title in the BetterDisplay style, e.g. "8-bit SDR RGB Full".
    var title: String {
        var t = "\(depth)-bit \(transferName) \(encodingName) \(rangeName)"
        if !colorimetryName.isEmpty { t += " · \(colorimetryName)" }
        return t
    }
}

/// One display timing (resolution/refresh) and the color modes it offers.
struct DisplayTiming: Identifiable, Hashable {
    let id: Int
    let width: Int
    let height: Int
    let refreshRateHz: Double
    let modes: [ColorModeEntry]

    var label: String {
        "\(width) × \(height) · \(refreshRateHz.formatted(.number.precision(.fractionLength(0...2)))) Hz"
    }
}

/// A physical external display with its driver-published timing table.
struct PhysicalDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let cgDirectDisplayID: CGDirectDisplayID
    let uuidString: String?
    let timings: [DisplayTiming]
    /// `DPTimingModeId` registry value: ID of the currently active timing.
    let currentTimingID: Int?
    let recordedLinkState: RecordedLinkState
    /// EDID from a matched framebuffer or a unique hardware-identity match.
    /// Raw bytes stay in memory until the user explicitly installs an override.
    let edid: Data?
    let liveConnection: LiveDisplayConnection?

    var legacySettingsID: String { "\(name)-\(cgDirectDisplayID)" }

    var configuredLinkMode: LinkDescription? {
        if case .recorded(let link) = recordedLinkState { return link }
        return nil
    }

    var currentTiming: DisplayTiming? {
        if let id = currentTimingID, let exact = timings.first(where: { $0.id == id }) {
            return exact
        }
        return nil
    }

    /// Color modes of the active timing, most preferred first.
    var currentModes: [ColorModeEntry] {
        (currentTiming?.modes ?? []).sorted {
            $0.score == $1.score ? $0.modeID < $1.modeID : $0.score > $1.score
        }
    }

    /// Formats advertised across all timings. This does not imply that each
    /// format is available for the currently active timing.
    var allSupportedModes: [ColorModeEntry] {
        let sorted = timings.flatMap(\.modes).sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.title != $1.title { return $0.title < $1.title }
            if $0.timingID != $1.timingID { return $0.timingID < $1.timingID }
            return $0.modeID < $1.modeID
        }
        var seen: Set<[Int]> = []
        return sorted.filter {
            seen.insert([$0.pixelEncoding, $0.depth, $0.dynamicRange, $0.eotf, $0.colorimetry]).inserted
        }
    }

    /// Only a unique record match can identify a row. The record does not
    /// contain colorimetry, so even this is not a live link verification.
    var configuredModeEntry: ColorModeEntry? {
        guard let link = configuredLinkMode else { return nil }
        let matches = currentModes.filter { link.matches($0) }
        return matches.count == 1 ? matches.first : nil
    }
}

/// Connection format as recorded by WindowServer
/// (`DisplaySets → Configs → DisplayConfig → LinkDescription`).
struct LinkDescription: Hashable {
    let range: Int
    let bitDepth: Int
    let eotf: Int
    let pixelEncoding: Int

    func matches(_ mode: ColorModeEntry) -> Bool {
        pixelEncoding == mode.pixelEncoding && bitDepth == mode.depth
            && range == mode.dynamicRange && eotf == mode.eotf
    }

    var title: String {
        let enc: String
        switch pixelEncoding {
        case 0: enc = "RGB"
        case 2: enc = "YCbCr 4:2:0"
        case 3: enc = "YCbCr 4:4:4"
        case 6: enc = "YCbCr 4:2:2"
        default: enc = "Encoding \(pixelEncoding)"
        }
        let transfer: String
        switch eotf {
        case 0: transfer = "SDR"
        case 1: transfer = "HDR"
        case 2: transfer = "HDR10"
        default: transfer = "EOTF \(eotf)"
        }
        let rangeName = range == 1 ? "Full" : (range == 0 ? "Limited" : "Range \(range)")
        return "\(bitDepth)-bit \(transfer) \(enc) \(rangeName)"
    }
}

enum RecordedLinkState: Hashable {
    case unavailable
    case conflicting
    case recorded(LinkDescription)
}

/// Reads the display topology from CoreGraphics + IORegistry; fully
/// independent of BetterDisplay.
///
/// Pairing chain: CG online displays → `SLSCopyDisplayInfoDictionary`
/// (`IODisplayLocation` carries the controller segment like `disp0@…`) →
/// the matching `IOMobileFramebufferShim` service (timing table + current
/// timing). Display names come from CoreDisplay's info dictionary.
enum DisplayCatalog {
    enum SnapshotError: Error { case onlineDisplaysUnavailable }

    static func snapshot() -> [PhysicalDisplay] {
        (try? snapshotResult().get()) ?? []
    }

    static func snapshotResult() -> Result<[PhysicalDisplay], SnapshotError> {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return .failure(.onlineDisplaysUnavailable)
        }
        if count == 0 { return .success([]) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return .failure(.onlineDisplaysUnavailable)
        }

        let shimsBySegment = framebufferShimsBySegment()
        let transportEDIDs = activeTransportEDIDs()
        let nameFor = Self.displayName
        let linkModes = WindowServerLinkModes.load()

        var displays: [PhysicalDisplay] = []
        for displayID in ids.prefix(Int(count)) where CGDisplayIsBuiltin(displayID) == 0 {
            let shim = controllerSegment(ofDisplay: displayID).flatMap { shimsBySegment[$0] }
            let name = nameFor(displayID) ?? "Display"
            let uuid = uuidString(of: displayID)
            let native = CoreDisplayModes.snapshot(for: displayID)
            let live = native.map {
                LiveDisplayConnection(currentMode: $0.currentMode, modes: $0.modes,
                                      isWritable: $0.isWritable && uuid != nil)
            }
            let edid = shim?.edid ?? matchingEDID(
                vendor: CGDisplayVendorNumber(displayID), product: CGDisplayModelNumber(displayID),
                serial: CGDisplaySerialNumber(displayID), candidates: transportEDIDs)
            displays.append(PhysicalDisplay(
                id: uuid.map { "uuid-\($0)" } ?? "\(name)-\(displayID)",
                name: name,
                cgDirectDisplayID: displayID,
                uuidString: uuid,
                timings: shim?.timings ?? [],
                currentTimingID: shim?.currentTimingID,
                recordedLinkState: uuid.flatMap { linkModes[$0] } ?? .unavailable,
                edid: edid,
                liveConnection: live))
        }
        return .success(displays.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }

    private static func uuidString(of displayID: CGDirectDisplayID) -> String? {
        guard let uuid = SLSBridge.uuid(for: displayID) else { return nil }
        guard let cfString = CFUUIDCreateString(nil, uuid) else { return nil }
        return (cfString as String).uppercased()
    }

    static func stableIdentity(for displayID: CGDirectDisplayID) -> String? {
        guard CGDisplayIsOnline(displayID) != 0 else { return nil }
        return uuidString(of: displayID).map { "uuid-\($0)" }
    }

    /// Some Apple Silicon systems publish EDID on a transport branch rather
    /// than the framebuffer. Reject repeated identities instead of guessing.
    static func matchingEDID(vendor: UInt32, product: UInt32, serial: UInt32, candidates: [Data]) -> Data? {
        guard vendor != 0, product != 0 else { return nil }
        let matches = candidates.filter { data in
            let bytes = [UInt8](data)
            guard bytes.count >= 128,
                  Array(bytes.prefix(8)) == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] else {
                return false
            }
            let edidVendor = UInt32(bytes[8]) << 8 | UInt32(bytes[9])
            let edidProduct = UInt32(bytes[10]) | UInt32(bytes[11]) << 8
            let edidSerial = UInt32(bytes[12]) | UInt32(bytes[13]) << 8
                | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24
            return edidVendor == vendor && edidProduct == product && edidSerial == serial
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func activeTransportEDIDs() -> [Data] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOPortTransportStateDisplayPort"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [Data] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let properties = registryProperties(of: service),
                  properties["Active"] as? Bool == true,
                  let metadata = properties["Metadata"] as? [String: Any],
                  let data = metadata["EDID"] as? Data else { continue }
            result.append(data)
        }
        return result
    }

    // MARK: - CG display → controller segment

    private static func controllerSegment(ofDisplay displayID: CGDirectDisplayID) -> String? {
        guard let dict = SLSBridge.copyDisplayInfoDictionary(displayID) as? [String: Any],
              let location = dict["IODisplayLocation"] as? String else { return nil }
        return location.split(separator: "/").first { $0.hasPrefix("disp") }.map(String.init)
    }

    private static func displayName(_ displayID: CGDirectDisplayID) -> String? {
        guard let dict = CoreDisplayBridge.displayInfoDictionary(displayID) as? [String: Any] else { return nil }
        // DisplayProductName is a localization table; any language value works.
        guard let localized = dict["DisplayProductName"] as? [String: Any] else {
            return dict["DisplayProductName"] as? String
        }
        for key in ["zh_CN", "en_US"] {
            if let name = localized[key] as? String { return name }
        }
        return localized.values.compactMap { $0 as? String }.first
    }

    // MARK: - Framebuffer shims

    private struct ShimInfo {
        var timings: [DisplayTiming]?
        var currentTimingID: Int?
        var edid: Data?
    }

    private static func framebufferShimsBySegment() -> [String: ShimInfo] {
        let matching = IOServiceMatching("IOMobileFramebufferShim")
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [String: ShimInfo] = [:]
        var ambiguous: Set<String> = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var pathBuffer = [CChar](repeating: 0, count: 512)
            guard IORegistryEntryGetPath(service, kIOServicePlane, &pathBuffer) == KERN_SUCCESS else { continue }
            let path = String(cString: pathBuffer)
            guard let segment = path.split(separator: "/").first(where: { $0.hasPrefix("disp") })
                .map(String.init) else { continue }
            guard let dict = registryProperties(of: service) else { continue }
            guard !ambiguous.contains(segment) else { continue }
            if result[segment] != nil {
                result.removeValue(forKey: segment)
                ambiguous.insert(segment)
                continue
            }
            let metadata = dict["Metadata"] as? [String: Any]
            result[segment] = ShimInfo(
                timings: parseTimings(dict["TimingElements"] as? [[String: Any]]),
                currentTimingID: dict["DPTimingModeId"] as? Int,
                edid: metadata?["EDID"] as? Data)
        }
        return result
    }

    static func parseTimings(_ raw: [[String: Any]]?) -> [DisplayTiming]? {
        guard let raw else { return nil }
        var timings: [DisplayTiming] = []
        for t in raw {
            guard let modesRaw = t["ColorModes"] as? [[String: Any]],
                  let timingID = t["ID"] as? Int,
                  let hAttr = t["HorizontalAttributes"] as? [String: Any],
                  let vAttr = t["VerticalAttributes"] as? [String: Any],
                  let width = hAttr["Active"] as? Int,
                  let height = vAttr["Active"] as? Int else { continue }
            // Refresh: vertical precise sync rate, 16.16 fixed-point.
            let vPrecise = vAttr["PreciseSyncRate"] as? Int ?? (vAttr["SyncRate"] as? Int ?? 0)
            var modes: [ColorModeEntry] = []
            for m in modesRaw {
                guard let modeID = m["ID"] as? Int,
                      let pixelEncoding = m["PixelEncoding"] as? Int,
                      let depth = m["Depth"] as? Int,
                      let dynamicRange = m["DynamicRange"] as? Int,
                      let eotf = m["EOTF"] as? Int,
                      let colorimetry = m["Colorimetry"] as? Int else { continue }
                modes.append(ColorModeEntry(
                    timingID: timingID,
                    modeID: modeID,
                    pixelEncoding: pixelEncoding,
                    depth: depth,
                    dynamicRange: dynamicRange,
                    eotf: eotf,
                    colorimetry: colorimetry,
                    score: m["Score"] as? Int ?? 0))
            }
            let grouped = Dictionary(grouping: modes, by: \.id)
            modes = grouped.values.compactMap { entries in
                Set(entries).count == 1 ? entries.first : nil
            }
            guard !modes.isEmpty else { continue }
            timings.append(DisplayTiming(id: timingID, width: width, height: height,
                                         refreshRateHz: Double(vPrecise) / 65536.0, modes: modes))
        }
        return timings.isEmpty ? nil : timings
    }

    private static func registryProperties(of service: io_object_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }
}

/// dlsym bridges for the two info dictionaries used above.
private enum SLSBridge {
    static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private static var initialized = false

    static func copyDisplayInfoDictionary(_ display: CGDirectDisplayID) -> CFDictionary? {
        typealias Fn = @convention(c) (UInt32) -> CFDictionary?
        guard let handle else { return nil }
        if !initialized {
            if let initFnRaw = dlsym(handle, "SLSMainConnectionID") {
                let initFn = unsafeBitCast(initFnRaw, to: (@convention(c) () -> UInt32).self)
                _ = initFn()
            }
            initialized = true
        }
        guard let raw = dlsym(handle, "SLSCopyDisplayInfoDictionary") else { return nil }
        return unsafeBitCast(raw, to: Fn.self)(display)
    }

    /// `CGDisplayCreateUUIDFromDisplayID` lives in SkyLight on current macOS.
    static func uuid(for display: CGDirectDisplayID) -> CFUUID? {
        typealias Fn = @convention(c) (UInt32) -> CFUUID?
        guard let handle, let raw = dlsym(handle, "CGDisplayCreateUUIDFromDisplayID") else { return nil }
        return unsafeBitCast(raw, to: Fn.self)(display)
    }
}

private enum CoreDisplayBridge {
    static let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL)

    static func displayInfoDictionary(_ display: CGDirectDisplayID) -> CFDictionary? {
        typealias Fn = @convention(c) (UInt32) -> CFDictionary?
        guard let handle, let raw = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(raw, to: Fn.self)(display)
    }

}

/// WindowServer stores historical configurations, not a live link readback.
/// Without an authoritative active-config marker, differing records are ambiguous.
enum WindowServerLinkModes {
    static func load() -> [String: RecordedLinkState] {
        let byHost = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/ByHost")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: byHost, includingPropertiesForKeys: nil) else { return [:] }

        var plists: [[String: Any]] = []
        for file in files where file.lastPathComponent.hasPrefix("com.apple.windowserver.displays.")
            && file.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil) as? [String: Any] else { continue }
            plists.append(plist)
        }
        return parse(plists)
    }

    static func parse(_ plists: [[String: Any]]) -> [String: RecordedLinkState] {
        var candidates: [String: Set<LinkDescription>] = [:]
        var incomplete: Set<String> = []
        for plist in plists {
            guard let sets = plist["DisplaySets"] as? [String: Any],
                  let configs = sets["Configs"] as? [[String: Any]] else { continue }
            for config in configs {
                guard let displayConfigs = config["DisplayConfig"] as? [[String: Any]] else { continue }
                for dc in displayConfigs {
                    guard let value = dc["UUID"] as? String else { continue }
                    let uuid = value.uppercased()
                    guard let link = dc["LinkDescription"] as? [String: Any] else { continue }
                    guard let range = link["Range"] as? Int,
                          let bitDepth = link["BitDepth"] as? Int,
                          let eotf = link["EOTF"] as? Int,
                          let pixelEncoding = link["PixelEncoding"] as? Int else {
                        incomplete.insert(uuid)
                        continue
                    }
                    candidates[uuid, default: []].insert(LinkDescription(
                        range: range, bitDepth: bitDepth, eotf: eotf, pixelEncoding: pixelEncoding))
                }
            }
        }
        var result: [String: RecordedLinkState] = [:]
        for (uuid, entries) in candidates {
            if entries.count > 1 {
                result[uuid] = .conflicting
            } else if let entry = entries.first {
                result[uuid] = .recorded(entry)
            }
        }
        for uuid in incomplete { result[uuid] = .unavailable }
        return result
    }
}
