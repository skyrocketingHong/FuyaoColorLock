import Foundation

/// Persisted configuration. Stored in UserDefaults so the app stays a single
/// small binary without extra files.
enum Settings {
    enum Keys {
        static let enabled = "guard.enabled"
        static let displayName = "guard.displayName"
        static let cliSpec = "guard.cliSpec"
        static let launchAtLogin = "guard.launchAtLogin"
        static let cliPath = "cli.path"
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    static var displayName: String {
        get { UserDefaults.standard.string(forKey: Keys.displayName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.displayName) }
    }

    static var preset: ConnectionModePreset {
        get {
            let spec = UserDefaults.standard.string(forKey: Keys.cliSpec)
                ?? ConnectionModePreset.presets[0].cliSpec
            return ConnectionModePreset.presets.first { $0.cliSpec == spec }
                ?? ConnectionModePreset.presets[0]
        }
        set { UserDefaults.standard.set(newValue.cliSpec, forKey: Keys.cliSpec) }
    }
}
