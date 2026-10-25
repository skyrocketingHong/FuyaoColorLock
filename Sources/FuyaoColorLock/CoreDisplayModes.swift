import CoreGraphics
import Foundation
import ObjectiveC

struct NativeConnectionMode: Identifiable, Hashable {
    let id: UInt64
    let width: Int
    let height: Int
    let refreshRateHz: Double
    let bitDepth: Int
    let colorMode: String
    let colorGamut: String
    let hdrMode: String
    let isVRR: Bool
    let isVirtual: Bool

    var timingLabel: String {
        "\(width) × \(height) · \(refreshRateHz.formatted(.number.precision(.fractionLength(0...2)))) Hz"
            + (isVRR ? " · VRR" : "")
    }

    var title: String {
        let gamut = colorGamut == "gamut_SRGB" ? "sRGB" : colorGamut
        return "\(bitDepth)-bit · \(hdrMode) · \(formatLabel) · \(gamut)"
    }

    var formatLabel: String {
        let value = colorMode.hasPrefix("HDR10_") ? String(colorMode.dropFirst(6)) : colorMode
        switch value {
        case "RGBFullRange": return "RGB Full"
        case "RGBLimitedRange": return "RGB Limited"
        case "YCbCr444LimitedRange", "444LimitedRange": return "YCbCr 4:4:4 Limited"
        case "YCbCr422LimitedRange", "422LimitedRange": return "YCbCr 4:2:2 Limited"
        case "YCbCr420LimitedRange", "420LimitedRange": return "YCbCr 4:2:0 Limited"
        case "YCbCr444FullRange", "444FullRange": return "YCbCr 4:4:4 Full"
        case "YCbCr422FullRange", "422FullRange": return "YCbCr 4:2:2 Full"
        case "YCbCr420FullRange", "420FullRange": return "YCbCr 4:2:0 Full"
        default: return colorMode
        }
    }

    func isCompatible(with current: NativeConnectionMode) -> Bool {
        !isVirtual && !current.isVirtual && width == current.width && height == current.height
            && refreshRateHz == current.refreshRateHz
            && hdrMode == current.hdrMode && isVRR == current.isVRR
    }
}

struct LiveDisplayConnection: Hashable {
    let currentMode: NativeConnectionMode
    let modes: [NativeConnectionMode]
    let isWritable: Bool
    let compatibleModes: [NativeConnectionMode]
    let otherModes: [NativeConnectionMode]

    init(currentMode: NativeConnectionMode, modes: [NativeConnectionMode], isWritable: Bool) {
        self.currentMode = currentMode
        self.modes = modes
        self.isWritable = isWritable
        compatibleModes = modes.filter { $0.isCompatible(with: currentMode) }
        otherModes = modes.filter { !$0.isCompatible(with: currentMode) }
    }
}

enum NativeApplyPolicy {
    enum Decision: Equatable { case unavailable, alreadyCurrent, ready }

    static func evaluate(target: NativeConnectionMode, expectedCurrent: NativeConnectionMode,
                         current: NativeConnectionMode?, available: [NativeConnectionMode], canSet: Bool,
                         identityMatches: Bool) -> Decision {
        guard identityMatches, canSet, let current, current == expectedCurrent, target.isCompatible(with: current),
              available.filter({ $0 == target }).count == 1 else { return .unavailable }
        return target == current ? .alreadyCurrent : .ready
    }
}

struct ModeReadbackVerifier {
    let expected: NativeConnectionMode
    private var consecutiveMatches = 0

    init(expected: NativeConnectionMode) { self.expected = expected }

    mutating func observe(_ current: NativeConnectionMode?) -> Bool {
        consecutiveMatches = current == expected ? consecutiveMatches + 1 : 0
        return consecutiveMatches >= 2
    }
}

/// Serializes the two explicit display-changing actions while their readback
/// or administrator authorization is pending.
@MainActor
enum DisplayMutationGate {
    private(set) static var isBusy = false

    static func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    static func end() { isBusy = false }
}

/// QuartzCore's native connection modes, verified against the runtime ABI.
/// All reads are independent of BetterDisplay. No guessed IORegistry mode IDs
/// are passed to the setter; only a freshly enumerated CADisplayMode is used.
enum CoreDisplayModes {
    enum ApplyRequest { case unavailable, alreadyCurrent, requested }

    private static let framework = dlopen(
        "/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY | RTLD_LOCAL)

    static func snapshot(for displayID: CGDirectDisplayID) -> LiveDisplayConnection? {
        guard let display = displayObject(for: displayID),
              let currentObject = object(display, "currentMode"),
              let current = mode(currentObject),
              let available = object(display, "availableModes") as? [NSObject] else { return nil }
        let modes = available.compactMap(mode).sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.refreshRateHz != $1.refreshRateHz { return $0.refreshRateHz > $1.refreshRateHz }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
        let uniqueIDs = Set(modes.map(\.id)).count == modes.count
        let containsCurrent = modes.filter { $0 == current }.count == 1
        return LiveDisplayConnection(currentMode: current, modes: uniqueIDs ? modes : [],
            isWritable: uniqueIDs && containsCurrent && setter(on: display) != nil
                && DisplayCatalog.stableIdentity(for: displayID) != nil)
    }

    @MainActor
    static func requestApply(_ target: NativeConnectionMode, to displayID: CGDirectDisplayID,
                             expectedCurrent: NativeConnectionMode, expectedDisplayIdentity: String) -> ApplyRequest {
        guard DisplayCatalog.stableIdentity(for: displayID) == expectedDisplayIdentity,
              let display = displayObject(for: displayID),
              let currentObject = object(display, "currentMode"),
              let current = mode(currentObject),
              let available = object(display, "availableModes") as? [NSObject],
              let implementation = setter(on: display) else { return .unavailable }
        switch NativeApplyPolicy.evaluate(target: target, expectedCurrent: expectedCurrent,
                                           current: current, available: available.compactMap(mode), canSet: true,
                                           identityMatches: true) {
        case .unavailable: return .unavailable
        case .alreadyCurrent: return .alreadyCurrent
        case .ready: break
        }
        let candidates = available.filter { mode($0) == target }
        guard candidates.count == 1, let selected = candidates.first,
              DisplayCatalog.stableIdentity(for: displayID) == expectedDisplayIdentity else { return .unavailable }
        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(implementation, to: Setter.self)(display, NSSelectorFromString("setCurrentMode:"), selected)
        return .requested
    }

    private static func displayObject(for displayID: CGDirectDisplayID) -> NSObject? {
        guard framework != nil, let cls = NSClassFromString("CADisplay") else { return nil }
        let selector = NSSelectorFromString("displays")
        guard let method = class_getClassMethod(cls, selector), valid(method, result: "@", arguments: 2) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        guard let displays = getter(cls, selector)?.takeUnretainedValue() as? [NSObject] else { return nil }
        let matches = displays.filter { uint32($0, "displayId") == displayID }
        return matches.count == 1 ? matches.first : nil
    }

    private static func mode(_ object: NSObject) -> NativeConnectionMode? {
        guard let id = uint64(object, "internalRepresentation"),
              let width = uint64(object, "width"), width > 0, width <= UInt64(Int.max),
              let height = uint64(object, "height"), height > 0, height <= UInt64(Int.max),
              let rate = double(object, "refreshRate"), rate.isFinite, rate > 0,
              let depth = uint64(object, "bitDepth"), depth > 0, depth <= 64,
              let colorMode = self.object(object, "colorMode") as? String,
              let gamut = self.object(object, "colorGamut") as? String,
              let hdr = self.object(object, "hdrMode") as? String,
              let vrr = bool(object, "isVRR"), let virtual = bool(object, "isVirtual") else { return nil }
        return NativeConnectionMode(id: id, width: Int(width), height: Int(height), refreshRateHz: rate,
            bitDepth: Int(depth), colorMode: colorMode, colorGamut: gamut, hdrMode: hdr,
            isVRR: vrr, isVirtual: virtual)
    }

    private static func checkedMethod(_ object: NSObject, _ name: String, result: String) -> Method? {
        guard let method = class_getInstanceMethod(object_getClass(object), NSSelectorFromString(name)),
              valid(method, result: result, arguments: 2) else { return nil }
        return method
    }

    private static func setter(on object: NSObject) -> IMP? {
        guard let method = class_getInstanceMethod(object_getClass(object), NSSelectorFromString("setCurrentMode:")),
              valid(method, result: "v", arguments: 3),
              let argument = method_copyArgumentType(method, 2) else { return nil }
        defer { free(argument) }
        guard String(cString: argument) == "@" else { return nil }
        return method_getImplementation(method)
    }

    private static func valid(_ method: Method, result: String, arguments: UInt32) -> Bool {
        guard method_getNumberOfArguments(method) == arguments else { return false }
        let type = method_copyReturnType(method)
        defer { free(type) }
        return String(cString: type) == result
    }

    private static func object(_ target: NSObject, _ name: String) -> NSObject? {
        guard let method = checkedMethod(target, name, result: "@") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(target, NSSelectorFromString(name))?
            .takeUnretainedValue() as? NSObject
    }

    private static func uint64(_ target: NSObject, _ name: String) -> UInt64? {
        guard let method = checkedMethod(target, name, result: "Q") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt64
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(target, NSSelectorFromString(name))
    }

    private static func uint32(_ target: NSObject, _ name: String) -> UInt32? {
        guard let method = checkedMethod(target, name, result: "I") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt32
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(target, NSSelectorFromString(name))
    }

    private static func double(_ target: NSObject, _ name: String) -> Double? {
        guard let method = checkedMethod(target, name, result: "d") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Double
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(target, NSSelectorFromString(name))
    }

    private static func bool(_ target: NSObject, _ name: String) -> Bool? {
        guard let method = checkedMethod(target, name, result: "B") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(target, NSSelectorFromString(name))
    }
}
