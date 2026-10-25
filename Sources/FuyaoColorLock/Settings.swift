import Foundation

struct DisplayPreference: Hashable {
    var legacyTargetID: String?
}

enum Settings {
    private static func modeLockKey(_ displayID: String) -> String { "nativeModeLock.v1.\(displayID)" }

    static func modeLockTarget(for displayID: String, defaults: UserDefaults = .standard) -> ModeLockTarget? {
        guard displayID.hasPrefix("uuid-"), let data = defaults.data(forKey: modeLockKey(displayID)),
              let target = try? JSONDecoder().decode(ModeLockTarget.self, from: data), target.isValid else { return nil }
        return target
    }

    static func setModeLockTarget(_ target: ModeLockTarget?, for displayID: String,
                                  defaults: UserDefaults = .standard) {
        guard displayID.hasPrefix("uuid-") else { return }
        guard let target else {
            defaults.removeObject(forKey: modeLockKey(displayID))
            return
        }
        guard target.isValid, let data = try? JSONEncoder().encode(target) else { return }
        defaults.set(data, forKey: modeLockKey(displayID))
    }

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
