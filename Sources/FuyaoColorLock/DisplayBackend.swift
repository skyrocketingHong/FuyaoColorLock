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

    static var live: DisplayBackend {
        DisplayBackend(
            snapshot: { DisplayCatalog.snapshotResult() },
            identity: { DisplayCatalog.stableIdentity(for: $0) },
            connection: { CoreDisplayModes.snapshot(for: $0) },
            requestApply: { CoreDisplayModes.requestApply($0, to: $1, expectedCurrent: $2, expectedDisplayIdentity: $3) },
            wait: { try await Task.sleep(nanoseconds: $0) },
            now: Date.init
        )
    }
}
