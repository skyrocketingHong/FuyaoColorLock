import AppKit
import SwiftUI

struct PanelContent: View {
    @ObservedObject var monitor: DisplayGuard
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var overrides: EDIDOverrideManager
    let showAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(isApplying: monitor.isApplying, refresh: monitor.reload)

            if !monitor.displays.isEmpty {
                DisplaySelectionRow(
                    choices: monitor.displays.map { DisplayMenuPicker.Choice(id: $0.id, name: $0.name) },
                    selection: selection,
                    selectedName: selectedDisplay?.name ?? ""
                )
                .padding(.horizontal, PanelMetrics.contentInset)
                .padding(.bottom, 12)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
                        Color.clear.frame(height: 0).id("display-content-start")

                        if monitor.refreshFailed {
                            Label("Display information could not be refreshed. Try again.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let display = selectedDisplay {
                            ColorModeSettingsView(display: display, monitor: monitor, overrides: overrides)

                            VStack(alignment: .leading, spacing: 10) {
                                PanelSectionTitle(title: "Installation configuration")
                                EDIDSettingsView(display: display, manager: overrides, lastRefreshAt: monitor.lastRefreshAt)
                                    .disabled(monitor.isApplying)
                            }
                        } else {
                            EmptyDisplayInformation()
                        }

                        AppSettingsView(showAbout: showAbout)
                    }
                    .padding(.horizontal, PanelMetrics.contentInset)
                    .padding(.bottom, PanelMetrics.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(PanelScrollEdges())
                .onPanelChange(of: presentation.selectedDisplayID) {
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
        .onPanelChange(of: monitor.displays.map(\.id), perform: reconcileSelection)
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
            Text("Fuyao Color Lock").font(.headline)
            Spacer(minLength: 0)
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 16, minHeight: 16)
            }
            .modifier(PanelActionStyle())
            .keyboardShortcut("r")
            .disabled(isApplying)
            .help("Refresh display information and check enabled mode locks. ⌘R")
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .padding(.vertical, 12)
    }
}

private struct DisplaySelectionRow: View {
    let choices: [DisplayMenuPicker.Choice]
    @Binding var selection: String
    let selectedName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisplayMenuPicker(choices: choices, selection: $selection)
                .frame(maxWidth: .infinity)
                .frame(minHeight: PanelMetrics.controlMinHeight)
            Text(selectedName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

private struct ColorModeSettingsView: View {
    let display: PhysicalDisplay
    @ObservedObject var monitor: DisplayGuard
    @ObservedObject var overrides: EDIDOverrideManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionTitle(title: "Color modes")
            InformationGroup("Live connection mode") {
                LiveModeInformation(connection: display.liveConnection, applyResult: monitor.applyResults[display.id])
                Divider()
                ModeLockView(
                    state: monitor.lockState(for: display),
                    isBusy: monitor.isApplying || overrides.isBusy,
                    setEnabled: { monitor.setModeLock($0, for: display) },
                    retry: { monitor.retryModeLock(for: display) }
                )
            }

            if let live = display.liveConnection {
                NativeModeInformation(connection: live, isBusy: monitor.isApplying || overrides.isBusy) { mode in
                    await monitor.apply(mode, to: display)
                }
            } else {
                SupportedModeInformation(
                    modes: display.currentTiming == nil ? display.allSupportedModes : display.currentModes,
                    hasCurrentTiming: display.currentTiming != nil
                )
            }

            DisplayDetailsView(display: display, preference: monitor.preference(for: display)) {
                monitor.clearTarget(for: display)
            }
        }
    }
}

private struct PanelFooter: View {
    let lastRefreshAt: Date?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let lastRefreshAt {
                HStack(spacing: 4) {
                    Text("Last read")
                    Text(lastRefreshAt, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { NSApp.terminate(nil) } label: { PanelActionLabel("Quit", minimumWidth: 44) }
                .modifier(PanelActionStyle())
                .keyboardShortcut("q")
                .disabled(isBusy)
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .padding(.vertical, 12)
    }
}
