import CoreGraphics
import Foundation

/// Establishes the connection used by read-only display discovery.
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

}
