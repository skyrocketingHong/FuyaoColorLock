import ServiceManagement
import SwiftUI

@main
struct FuyaoColorLockApp: App {
    @StateObject private var guard_ = DisplayGuard()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(guard_: guard_)
        } label: {
            Image(systemName: guard_.phase.isHealthy ? "lock.fill" : "lock.open.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    @ObservedObject var guard_: DisplayGuard
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(statusLine)
            .font(.system(size: 11, weight: .regular))

        Divider()

        Toggle(String(localized: "Lock color mode", comment: "toggle lock"), isOn: lockEnabled)
        Picker(String(localized: "Display", comment: "display picker"), selection: displayBinding) {
            ForEach(guard_.availableDisplays, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        Picker(String(localized: "Mode", comment: "mode picker"), selection: presetBinding) {
            ForEach(ConnectionModePreset.presets) { preset in
                Text(preset.title).tag(preset)
            }
        }
        Button(String(localized: "Re-apply now", comment: "manual apply")) {
            Task { await guard_.applyNow() }
        }
        .disabled(!Settings.isEnabled)

        Divider()

        Toggle(String(localized: "Launch at Login", comment: "login item"), isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { enabled in
                updateLoginItem(enabled)
            }
        Button(String(localized: "Refresh display list", comment: "refresh displays")) {
            guard_.refreshDisplayList()
        }

        Divider()

        Button(String(localized: "Quit FuyaoColorLock", comment: "quit")) {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusLine: String {
        guard_.phase.summary
    }

    /// Settings are stored synchronously; re-check the target display afterwards
    /// so a mode switch from the menu takes effect immediately.
    private var lockEnabled: Binding<Bool> {
        Binding(
            get: { Settings.isEnabled },
            set: { newValue in
                Settings.isEnabled = newValue
                if newValue {
                    guard_.scheduleCheck(delay: 0.2)
                }
            }
        )
    }

    private var displayBinding: Binding<String> {
        Binding(
            get: { Settings.displayName },
            set: { newValue in
                guard guard_.availableDisplays.contains(newValue) else { return }
                Settings.displayName = newValue
                guard_.scheduleCheck(delay: 0.2)
            }
        )
    }

    private var presetBinding: Binding<ConnectionModePreset> {
        Binding(
            get: { Settings.preset },
            set: { newValue in
                Settings.preset = newValue
                guard_.scheduleCheck(delay: 0.2)
            }
        )
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registering fails when the binary runs outside an app bundle.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
