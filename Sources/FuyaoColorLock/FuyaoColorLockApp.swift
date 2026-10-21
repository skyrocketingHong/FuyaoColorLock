import ServiceManagement
import SwiftUI

@main
struct FuyaoColorLockApp: App {
    @StateObject private var guard_ = DisplayGuard()

    var body: some Scene {
        MenuBarExtra {
            PanelContent(guard_: guard_)
        } label: {
            Image(systemName: lockedAny ? "lock.fill" : "lock.open.fill")
        }
        .menuBarExtraStyle(.window)
    }

    private var lockedAny: Bool {
        guard_.displays.contains { Settings.isLocked($0.id) }
    }
}

private struct PanelContent: View {
    @ObservedObject var guard_: DisplayGuard
    @State private var selectedDisplayID: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if guard_.displays.isEmpty {
                Text("No external display with a color mode table found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                tabs
                if let display = currentDisplay {
                    DisplaySection(display: display)
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
        .onAppear {
            if selectedDisplayID == nil {
                selectedDisplayID = guard_.displays.first?.id
            }
        }
        .onChange(of: guard_.displays) { displays in
            if let id = selectedDisplayID, displays.contains(where: { $0.id == id }) { return }
            selectedDisplayID = displays.first?.id
        }
    }

    private var header: some View {
        HStack {
            Text("Fuyao Color Lock")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let action = guard_.lastAction {
                Text(action)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var tabs: some View {
        Picker("Display", selection: $selectedDisplayID) {
            ForEach(guard_.displays) { display in
                Text(display.name).tag(Optional(display.id))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var currentDisplay: PhysicalDisplay? {
        guard_.displays.first { $0.id == selectedDisplayID }
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 11))
                .onChange(of: launchAtLogin) { enabled in
                    updateLoginItem(enabled)
                }
            Spacer()
            Button("Re-apply") { guard_.reassertNow() }
                .font(.system(size: 11))
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11))
        }
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

/// One display tab: current timing, the color modes the driver actually
/// offers on it, and an independent lock with its own pinned mode.
private struct DisplaySection: View {
    let display: PhysicalDisplay

    private var savedTarget: String? { Settings.targetModeID(display.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(display.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let timing = display.currentTiming {
                    Text("current timing: \(timing.label)")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("timing unknown")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Lock color mode", isOn: lockBinding)
                .font(.system(size: 11))

            modeList

            if let target = savedTarget, let entry = display.currentModes.first(where: { $0.id == target }) {
                Text("Pinned: \(entry.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("No mode pinned — macOS picks after each link reset. Select a mode to pin it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { Settings.isLocked(display.id) },
            set: { Settings.setLocked(display.id, $0) }
        )
    }

    /// Color modes of the active timing, most preferred first. Nothing is
    /// selected by default; the top row reflects the driver preference.
    private var modeList: some View {
        VStack(alignment: .leading, spacing: 2) {
            let modes = display.currentTiming?.modes.sorted { $0.score > $1.score } ?? []
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                ModeRow(
                    title: mode.title,
                    subtitle: index == 0 ? "driver default" : nil,
                    isSelected: savedTarget == mode.id
                ) { select(mode) }
            }
        }
    }

    private func select(_ mode: ColorModeEntry) {
        if savedTarget == mode.id {
            Settings.setTargetModeID(display.id, nil)
        } else {
            Settings.setTargetModeID(display.id, mode.id)
            if !Settings.isLocked(display.id) {
                Settings.setLocked(display.id, true)
            }
        }
    }
}

private struct ModeRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "smallcircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 11).monospaced())
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
