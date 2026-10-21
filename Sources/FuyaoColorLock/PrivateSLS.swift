import CoreGraphics
import Foundation

/// dlsym wrappers for the SkyLight entry points Fuyao Color Lock needs.
/// CGS mode APIs were verified on macOS 27 (signatures recovered by disassembly):
/// - CGSGetNumberOfDisplayModes(display, &count)
/// - CGSGetCurrentDisplayMode(display, &modeID)
/// - CGSGetDisplayModeDescriptionOfLength(display, index, desc(0xD4 bytes), 0xD4)
/// - CGSConfigureDisplayMode(config, display, modeID) inside a CG display transaction
/// - SLSDetectDisplays()
enum PrivateSLS {
    static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)

    private static func symbol<T>(_ name: String) -> T? {
        handle.flatMap { dlsym($0, name).map { unsafeBitCast($0, to: T.self) } }
    }

    /// Establishes the WindowServer connection the other calls rely on.
    static func ensureConnection() -> Bool {
        let initConn = symbol("SLSMainConnectionID") as (@convention(c) () -> UInt32)?
        guard let initConn else { return false }
        _ = initConn()
        return true
    }

    static func detectDisplays() -> Bool {
        let detect = symbol("SLSDetectDisplays") as (@convention(c) () -> Int32)?
        return detect?() == 0
    }

    /// Current desktop (CGS) mode index for a display.
    static func currentModeID(display: CGDirectDisplayID) -> UInt32? {
        typealias Fn = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>) -> Int32
        guard let fn = symbol("CGSGetCurrentDisplayMode") as Fn? else { return nil }
        var modeID: UInt32 = 0
        guard fn(display, &modeID) == 0 else { return nil }
        return modeID
    }

    struct ModeSummary {
        let width: UInt32
        let height: UInt32
        let refreshHz: Double
    }

    /// Reads the 0xD4-byte CGSDisplayModeDescription for a mode index.
    /// Layout recovered on macOS 27: modeID@0, width@8, height@0xC,
    /// refresh (integer Hz)@0x24, pixelEncoding@0x30.
    static func modeSummary(display: CGDirectDisplayID, index: Int) -> ModeSummary? {
        typealias Fn = @convention(c) (UInt32, Int32, UnsafeMutableRawPointer, Int) -> Int32
        guard let fn = symbol("CGSGetDisplayModeDescriptionOfLength") as Fn? else { return nil }
        var buffer = [UInt8](repeating: 0, count: 0xD4)
        guard fn(display, Int32(index), &buffer, 0xD4) == 0 else { return nil }
        func u32(_ offset: Int) -> UInt32 {
            let b0 = UInt32(buffer[offset])
            let b1 = UInt32(buffer[offset + 1])
            let b2 = UInt32(buffer[offset + 2])
            let b3 = UInt32(buffer[offset + 3])
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        return ModeSummary(width: u32(8), height: u32(0xC), refreshHz: Double(u32(0x24)))
    }

    /// Applies a CGS mode within a standard display transaction. Changing the
    /// desktop timing makes the driver reprogram the link, which re-runs the
    /// display-mode selection (bounded by the installed EDID override).
    static func applyMode(display: CGDirectDisplayID, modeID: UInt32) -> Bool {
        typealias Fn = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
        guard let configure = symbol("CGSConfigureDisplayMode") as Fn? else { return false }
        var config: OpaquePointer?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard configure(config, display, modeID) == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, CGConfigureOption(rawValue: 2)) == .success
    }
}
