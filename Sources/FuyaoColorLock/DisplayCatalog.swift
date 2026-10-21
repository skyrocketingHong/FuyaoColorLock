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

    var rangeName: String { dynamicRange == 1 ? "Full" : "Limited" }

    var transferName: String {
        switch eotf {
        case 0: return "SDR"
        case 1: return "HDR"
        case 2: return "HDR10"
        default: return "EOTF \(eotf)"
        }
    }

    var colorimetryName: String {
        switch colorimetry {
        case 0, 1: return "" // ITU defaults, same label BetterDisplay shows without suffix
        case 7: return "BT.2020"
        case 9: return "P3"
        case 10: return "sRGB"
        case 16: return "Panel Native"
        default: return "Colorimetry \(colorimetry)"
        }
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

    var label: String { "\(width)×\(height) @ \(String(format: "%.0f", refreshRateHz))Hz" }
}

/// A physical external display with its driver-published timing table.
struct PhysicalDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let cgDirectDisplayID: CGDirectDisplayID
    let timings: [DisplayTiming]
    /// `DPTimingModeId` registry value: ID of the currently active timing.
    let currentTimingID: Int?

    var currentTiming: DisplayTiming? {
        if let id = currentTimingID, let exact = timings.first(where: { $0.id == id }) {
            return exact
        }
        // Fallback while the driver has not published the active timing ID
        // (e.g. right after a link reset): the timing with the best-scoring
        // mode is the panel's preferred one.
        return timings.max { a, b in
            (a.modes.map(\.score).max() ?? 0) < (b.modes.map(\.score).max() ?? 0)
        }
    }

    /// Color modes of the active timing, most preferred first.
    var currentModes: [ColorModeEntry] {
        (currentTiming?.modes ?? []).sorted { $0.score > $1.score }
    }
}

/// Reads the display topology from CoreGraphics + IORegistry; fully
/// independent of BetterDisplay.
///
/// Pairing chain: CG online displays → `SLSCopyDisplayInfoDictionary`
/// (`IODisplayLocation` carries the controller segment like `disp0@…`) →
/// the matching `IOMobileFramebufferShim` service (timing table + current
/// timing). Display names come from CoreDisplay's info dictionary.
enum DisplayCatalog {
    static func snapshot() -> [PhysicalDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }

        let shimsBySegment = framebufferShimsBySegment()
        let nameFor = Self.displayName

        var displays: [PhysicalDisplay] = []
        for displayID in ids.prefix(Int(count)) where CGDisplayIsBuiltin(displayID) == 0 {
            guard let segment = controllerSegment(ofDisplay: displayID),
                  let shim = shimsBySegment[segment],
                  let timings = shim.timings, !timings.isEmpty else { continue }
            let name = nameFor(displayID) ?? "Display"
            displays.append(PhysicalDisplay(
                id: "\(name)-\(displayID)",
                name: name,
                cgDirectDisplayID: displayID,
                timings: timings,
                currentTimingID: shim.currentTimingID))
        }
        return displays
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
    }

    private static func framebufferShimsBySegment() -> [String: ShimInfo] {
        let matching = IOServiceMatching("IOMobileFramebufferShim")
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [String: ShimInfo] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var pathBuffer = [CChar](repeating: 0, count: 512)
            guard IORegistryEntryGetPath(service, kIOServicePlane, &pathBuffer) == KERN_SUCCESS else { continue }
            let path = String(cString: pathBuffer)
            guard let segment = path.split(separator: "/").first(where: { $0.hasPrefix("disp") })
                .map(String.init) else { continue }
            guard let dict = registryProperties(of: service) else { continue }
            result[segment] = ShimInfo(
                timings: parseTimings(dict["TimingElements"] as? [[String: Any]]),
                currentTimingID: dict["DPTimingModeId"] as? Int)
        }
        return result
    }

    private static func parseTimings(_ raw: [[String: Any]]?) -> [DisplayTiming]? {
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
                guard let modeID = m["ID"] as? Int else { continue }
                modes.append(ColorModeEntry(
                    timingID: timingID,
                    modeID: modeID,
                    pixelEncoding: m["PixelEncoding"] as? Int ?? 0,
                    depth: m["Depth"] as? Int ?? 8,
                    dynamicRange: m["DynamicRange"] as? Int ?? 0,
                    eotf: m["EOTF"] as? Int ?? 0,
                    colorimetry: m["Colorimetry"] as? Int ?? 0,
                    score: m["Score"] as? Int ?? 0))
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
}

private enum CoreDisplayBridge {
    static let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL)

    static func displayInfoDictionary(_ display: CGDirectDisplayID) -> CFDictionary? {
        typealias Fn = @convention(c) (UInt32) -> CFDictionary?
        guard let handle, let raw = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(raw, to: Fn.self)(display)
    }
}
