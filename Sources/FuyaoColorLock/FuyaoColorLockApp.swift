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

    /// Critically-damped spring (Apple house style): no overshoot for a
    /// panel resize that is not gesture-driven.
    private let resize = Animation.spring(response: 0.35, dampingFraction: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if guard_.displays.isEmpty {
                emptyState
            } else {
                tabs
                if let display = currentDisplay {
                    DisplaySection(display: display, guard_: guard_)
                        .id(display.id)
                        .transition(.opacity)
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .animation(resize, value: selectedDisplayID)
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
        HStack(alignment: .firstTextBaseline) {
            Text("Fuyao Color Lock")
                .font(.headline)
            Spacer()
            if let action = guard_.lastAction {
                Text(action)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(action)
            }
        }
    }

    private var emptyState: some View {
        Text("No external display with a color mode table found.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
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
                .font(.footnote)
                .onChange(of: launchAtLogin) { enabled in
                    updateLoginItem(enabled)
                }
            Spacer()
            ReapplyButton { guard_.reassertNow() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.footnote)
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

/// Primary action: Liquid Glass on macOS 26+, plain equivalent elsewhere.
private struct ReapplyButton: View {
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Label("Re-apply", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        } else {
            Button(action: action) {
                Label("Re-apply", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
            }
            .controlSize(.small)
        }
    }
}

/// One display tab: current timing, the color modes the driver actually
/// offers on it, the macOS-recorded current mode, and an independent lock.
private struct DisplaySection: View {
    let display: PhysicalDisplay
    @ObservedObject var guard_: DisplayGuard

    private var savedTarget: String? { Settings.targetModeID(display.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let timing = display.currentTiming {
                    Text(timing.label)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            currentModeBanner

            Toggle("Lock color mode", isOn: lockBinding)
                .font(.footnote)

            modeList

            hint
        }
    }

    private var currentModeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: display.configuredModeEntry != nil ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(display.configuredModeEntry != nil ? .green : .secondary)
            Text(currentModeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var currentModeText: String {
        if let entry = display.configuredModeEntry {
            return String(localized: "Current: \(entry.title)", comment: "current mode banner")
        }
        if let link = display.configuredLinkMode {
            return String(localized: "Recorded: \(link.title)", comment: "recorded but unmatched")
        }
        return String(localized: "Current mode: chosen automatically by macOS", comment: "no record")
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { Settings.isLocked(display.id) },
            set: { Settings.setLocked(display.id, $0) }
        )
    }

    /// Color modes of the active timing, most preferred first. The macOS-
    /// recorded entry (when it matches a listed mode) is marked "current";
    /// nothing is force-selected — pinning is an explicit user choice.
    private var modeList: some View {
        let modes = display.currentModes
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                ModeRow(
                    title: mode.title,
                    subtitle: index == 0 ? "driver default" : nil,
                    isCurrent: display.configuredModeEntry?.id == mode.id,
                    isSelected: savedTarget == mode.id
                ) { select(mode) }
                if index < modes.count - 1 {
                    Divider().padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 4)
        .background(.quinary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hint: some View {
        Text("Pinning records the target and re-detects the display after link resets. YCbCr modes can be removed for good with the EDID override (see README).")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func select(_ mode: ColorModeEntry) {
        if savedTarget == mode.id {
            Settings.setTargetModeID(display.id, nil)
        } else {
            Settings.setTargetModeID(display.id, mode.id)
            if !Settings.isLocked(display.id) {
                Settings.setLocked(display.id, true)
            }
            // Give immediate feedback: re-run detection so the pinned target
            // becomes the reference for the next mode selection.
            guard_.reassertNow()
        }
    }
}

private struct ModeRow: View {
    let title: String
    let subtitle: String?
    let isCurrent: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "smallcircle.fill.circle" : "circle")
                    .font(.footnote)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.footnote.monospacedDigit())
                    .lineLimit(1)
                if isCurrent {
                    Text("current")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
