import Foundation

/// Per-display persisted configuration. Keys are the PhysicalDisplay id
/// (product name + EDID digest) so settings survive reconnects.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    private static func lockKey(_ displayID: String) -> String { "lock.\(displayID).enabled" }
    private static func targetKey(_ displayID: String) -> String { "lock.\(displayID).targetModeID" }
    private static let launchKey = "app.launchAtLogin"

    static func isLocked(_ displayID: String) -> Bool {
        defaults.bool(forKey: lockKey(displayID))
    }

    static func setLocked(_ displayID: String, _ locked: Bool) {
        defaults.set(locked, forKey: lockKey(displayID))
    }

    /// Selected color mode entry id ("timingID-modeID"), or nil when nothing
    /// is pinned yet (the default state).
    static func targetModeID(_ displayID: String) -> String? {
        defaults.string(forKey: targetKey(displayID))
    }

    static func setTargetModeID(_ displayID: String, _ modeID: String?) {
        defaults.set(modeID, forKey: targetKey(displayID))
    }

    static var anyLockEnabled: Bool {
        guard let keys = defaults.dictionaryRepresentation().keys as? [String] else { return false }
        return keys.contains { $0.hasPrefix("lock.") && $0.hasSuffix(".enabled") && defaults.bool(forKey: $0) }
    }
}
