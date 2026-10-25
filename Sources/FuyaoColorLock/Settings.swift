import Foundation

struct DisplayPreference: Hashable {
    var legacyTargetID: String?
}

enum Settings {
    static func preference(for display: PhysicalDisplay, defaults: UserDefaults = .standard) -> DisplayPreference {
        // A legacy numeric ID has no format fingerprint. Even if that ID is
        // reused in today's table, its original color format is not recoverable.
        DisplayPreference(legacyTargetID: defaults.string(
            forKey: "lock.\(display.legacySettingsID).targetModeID"))
    }

    static func clearTarget(for display: PhysicalDisplay, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "lock.\(display.legacySettingsID).targetModeID")
        defaults.removeObject(forKey: "lock.\(display.legacySettingsID).enabled")
    }
}
