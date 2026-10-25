import AppKit
import ServiceManagement
import SwiftUI

struct PanelContent: View {
    @ObservedObject var monitor: DisplayGuard
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var overrides: EDIDOverrideManager

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(isApplying: monitor.isApplying, refresh: monitor.reload)

            if !monitor.displays.isEmpty {
                Picker("Display", selection: selection) {
                    ForEach(monitor.displays) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 0).id("display-content-start")

                        if monitor.refreshFailed {
                            Label("Display information could not be refreshed. Try again.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let display = selectedDisplay {
                            DisplayInformation(
                                display: display,
                                preference: monitor.preference(for: display),
                                overrides: overrides,
                                lastRefreshAt: monitor.lastRefreshAt,
                                isApplying: monitor.isApplying,
                                applyResult: monitor.applyResults[display.id],
                                applyMode: { mode in await monitor.apply(mode, to: display) },
                                clearTarget: { monitor.clearTarget(for: display) }
                            )
                        } else {
                            EmptyDisplayInformation()
                        }

                        if let action = monitor.lastAction {
                            Text(action)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: presentation.selectedDisplayID) { _ in
                    proxy.scrollTo("display-content-start", anchor: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            PanelFooter(lastRefreshAt: monitor.lastRefreshAt, isBusy: monitor.isApplying || overrides.isBusy)
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .clipped()
        .onAppear(perform: reconcileSelection)
        .onChange(of: monitor.displays.map(\.id)) { _ in reconcileSelection() }
    }

    private var selectedDisplay: PhysicalDisplay? {
        monitor.displays.first { $0.id == presentation.selectedDisplayID } ?? monitor.displays.first
    }

    private var selection: Binding<String> {
        Binding(
            get: { selectedDisplay?.id ?? "" },
            set: { presentation.selectedDisplayID = $0 }
        )
    }

    private func reconcileSelection() {
        guard !monitor.displays.contains(where: { $0.id == presentation.selectedDisplayID }) else { return }
        presentation.selectedDisplayID = monitor.displays.first?.id
    }
}

private struct PanelHeader: View {
    let isApplying: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fuyao Color Lock").font(.headline)
                Text("Display connection information")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(isApplying)
            .help("Read display information again without changing display settings. ⌘R")
        }
        .padding(16)
    }
}

private struct EmptyDisplayInformation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No external display", systemImage: "display")
                .font(.headline)
            Text("Connect or wake an external display, then refresh. Some displays do not expose a connection mode table to macOS.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }
}

private struct DisplayInformation: View {
    let display: PhysicalDisplay
    let preference: DisplayPreference
    @ObservedObject var overrides: EDIDOverrideManager
    let lastRefreshAt: Date?
    let isApplying: Bool
    let applyResult: ModeApplyResult?
    let applyMode: (NativeConnectionMode) async -> Void
    let clearTarget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(display.name)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if display.liveConnection == nil, let timing = display.currentTiming {
                    Text(timing.label)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if display.liveConnection == nil {
                    Text("Current resolution and refresh rate are unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LiveModeInformation(connection: display.liveConnection, applyResult: applyResult)

            EDIDSettingsView(display: display, manager: overrides, lastRefreshAt: lastRefreshAt)
                .disabled(isApplying)

            if let live = display.liveConnection {
                NativeModeInformation(
                    connection: live,
                    isBusy: isApplying || overrides.isBusy,
                    applyMode: applyMode
                )
            } else {
                SupportedModeInformation(
                    modes: display.currentTiming == nil ? display.allSupportedModes : display.currentModes,
                    hasCurrentTiming: display.currentTiming != nil
                )
            }

            DisclosureGroup("Saved macOS record") {
                RecordedModeInformation(state: display.recordedLinkState)
                    .padding(.top, 8)
            }

            if let targetID = preference.legacyTargetID {
                SavedTargetInformation(targetID: targetID, clear: clearTarget)
            }

            DisclosureGroup("Driver table details (read only)") {
                VStack(alignment: .leading, spacing: 14) {
                    if display.liveConnection != nil {
                        SupportedModeInformation(
                            modes: display.currentTiming == nil ? display.allSupportedModes : display.currentModes,
                            hasCurrentTiming: display.currentTiming != nil
                        )
                    }
                    ReportedTimingInformation(timings: display.timings, currentTimingID: display.currentTimingID)
                }
                .padding(.top, 8)
            }

            Text("Connection formats are separate from ICC color profiles. System read-back does not measure the display's physical color output.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RecordedModeInformation: View {
    let state: RecordedLinkState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .recorded(let link):
                Text(link.title)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Saved by macOS; may differ from the live connection. The record does not include colorimetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Label("No usable record", systemImage: "questionmark.circle")
                Text("macOS has not provided a complete connection record. The active format cannot be determined.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .conflicting:
                Label("Conflicting records", systemImage: "exclamationmark.triangle")
                Text("macOS has multiple different records for this display. None is presented as the active format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SavedTargetInformation: View {
    let targetID: String
    let clear: () -> Void

    var body: some View {
        InformationGroup("Previously saved target") {
            Text(targetID)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("The old target cannot be reliably restored from its ID. Saving it did not apply a display mode.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear saved target", action: clear)
                .help("Remove the saved preference without changing the display.")
        }
    }

}

private struct SupportedModeInformation: View {
    let modes: [ColorModeEntry]
    let hasCurrentTiming: Bool

    var body: some View {
        InformationGroup("Driver-reported modes") {
            Label("Driver table · View only", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !hasCurrentTiming, !modes.isEmpty {
                Text("Formats reported across all supported timings. The current timing is unknown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Colorimetry codes are shown as reported by the driver; their color space mapping is unverified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if modes.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(modes) { mode in
                        ReadOnlyModeRow(mode: mode)
                        if mode.id != modes.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        hasCurrentTiming
            ? "No modes were reported for the current timing."
            : "Modes will appear when the driver reports the current timing."
    }
}

private struct ReportedTimingInformation: View {
    let timings: [DisplayTiming]
    let currentTimingID: Int?

    var body: some View {
        InformationGroup("Reported display timings") {
            Text("Resolution and refresh rate options are read only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(timings) { timing in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timing.label)
                            .font(.callout.monospacedDigit())
                            .textSelection(.enabled)
                        if timing.id == currentTimingID {
                            Text("Current timing reported by driver")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ReadOnlyModeRow: View {
    let mode: ColorModeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode.title)
                .font(.callout.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Read-only driver entry.")
    }
}

struct InformationGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct PanelFooter: View {
    let lastRefreshAt: Date?
    let isBusy: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastRefreshAt {
                HStack(spacing: 4) {
                    Text("Last read")
                    Text(lastRefreshAt, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: updateLoginItem))
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .disabled(isBusy)
            }

            if needsApproval {
                Button("Allow in Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Login item could not be changed", isPresented: Binding(
            get: { loginError != nil },
            set: { if !$0 { loginError = nil } }
        )) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "")
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
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
