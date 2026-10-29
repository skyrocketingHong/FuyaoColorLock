import CoreGraphics
import Foundation

/// A narrow dependency boundary for deterministic lock tests. Production uses
/// the native bridge; tests substitute snapshots and never call the setter.
@MainActor
struct DisplayBackend {
    var snapshot: () -> Result<[PhysicalDisplay], DisplayCatalog.SnapshotError>
    var identity: (CGDirectDisplayID) -> String?
    var connection: (CGDirectDisplayID) -> LiveDisplayConnection?
    var requestApply: (NativeConnectionMode, CGDirectDisplayID, NativeConnectionMode, String) -> CoreDisplayModes.ApplyRequest
    var wait: (UInt64) async throws -> Void
    var now: () -> Date
    var displayIsAsleep: (CGDirectDisplayID) -> Bool? = { _ in nil }
    var sessionAvailable: () -> Bool? = { true }
    var onlineDisplayIDs: () -> Set<CGDirectDisplayID>? = { nil }

    static var live: DisplayBackend {
        DisplayBackend(
            snapshot: { DisplayCatalog.snapshotResult() },
            identity: { DisplayCatalog.stableIdentity(for: $0) },
            connection: { CoreDisplayModes.snapshot(for: $0) },
            requestApply: { CoreDisplayModes.requestApply($0, to: $1, expectedCurrent: $2, expectedDisplayIdentity: $3) },
            wait: { try await Task.sleep(nanoseconds: $0) },
            now: Date.init,
            displayIsAsleep: { id in
                guard CGDisplayIsOnline(id) != 0 else { return nil }
                return CGDisplayIsAsleep(id) != 0
            },
            sessionAvailable: {
                guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
                      let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool,
                      let loginDone = session[kCGSessionLoginDoneKey as String] as? Bool else { return nil }
                return onConsole && loginDone
                    // This optional private hint is absent when unlocked on
                    // current macOS. Only a known true value suppresses writes.
                    && session["CGSSessionScreenIsLocked"] as? Bool != true
            },
            onlineDisplayIDs: {
                var count: UInt32 = 0
                guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
                guard count > 0 else { return [] }
                var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
                guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
                return Set(ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 })
            }
        )
    }
}
