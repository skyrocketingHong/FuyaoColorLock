import AppKit
import SwiftUI

struct PanelContent: View {
    @ObservedObject var monitor: DisplayGuard
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var overrides: EDIDOverrideManager
    let showAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                displayName: selectedDisplay?.name,
                choices: monitor.displays.map { DisplayMenuPicker.Choice(id: $0.id, name: $0.name) },
                selection: selection,
                isApplying: monitor.isApplying,
                refresh: monitor.reload
            )

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
                        Color.clear.frame(height: 0).id("display-content-start")

                        if monitor.refreshFailed {
                            Label("Couldn't refresh. Try again.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let display = selectedDisplay {
                            ColorModeSettingsView(display: display, monitor: monitor, overrides: overrides)
                            EDIDSettingsView(display: display, manager: overrides, lastRefreshAt: monitor.lastRefreshAt)
                                .disabled(monitor.isApplying)
                        } else if !monitor.refreshFailed {
                            EmptyDisplayInformation(issue: presentation.selectionIssue,
                                                    hasOtherDisplays: !monitor.displays.isEmpty)
                        }

                        AppSettingsView(showAbout: showAbout, isBusy: monitor.isApplying || overrides.isBusy)
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
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .clipped()
        .onAppear(perform: reconcileSelection)
        .onPanelChange(of: monitor.displays.map(\.id), perform: reconcileSelection)
    }

    private var selectedDisplay: PhysicalDisplay? {
        monitor.displays.first { $0.id == presentation.selectedDisplayID }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { presentation.selectedDisplayID },
            set: { presentation.selectDisplay($0, displays: monitor.displays) }
        )
    }

    private func reconcileSelection() {
        presentation.reconcile(displays: monitor.displays)
    }
}
private struct PanelHeader: View {
    let displayName: String?
    let choices: [DisplayMenuPicker.Choice]
    @Binding var selection: String?
    let isApplying: Bool
    let refresh: () -> Void

    var body: some View {
        PanelControlRow(minimumLabelWidth: 160) {
            if let displayName {
                Text(displayName)
                    .font(.headline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Displays").font(.headline)
            }
        } control: {
            HStack(spacing: PanelMetrics.rowSpacing) {
                if choices.count > 1 || (selection == nil && !choices.isEmpty) {
                    DisplayMenuPicker(choices: choices, selection: $selection)
                }
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
        }
        .padding(.horizontal, PanelMetrics.contentInset)
        .padding(.vertical, 12)
    }
}

private struct EmptyDisplayInformation: View {
    let issue: DisplaySelectionIssue?
    let hasOtherDisplays: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            Label(title, systemImage: "display")
                .font(.headline)
            Text(hasOtherDisplays ? LocalizedStringKey("Choose a display from Other displays.")
                                  : LocalizedStringKey("Connect an external display, then refresh."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }

    private var title: LocalizedStringKey {
        switch issue {
        case .unknownScreen: return "Couldn't identify this screen."
        case .unavailableDisplay: return "Display unavailable."
        case .ambiguousScreen: return "Choose a display for this screen."
        case nil: return "No external display"
        }
    }
}

private struct ColorModeSettingsView: View {
    let display: PhysicalDisplay
    @ObservedObject var monitor: DisplayGuard
    @ObservedObject var overrides: EDIDOverrideManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InformationGroup("Color mode") {
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

            DisplayDetailsView(display: display, preference: monitor.preference(for: display), lastRefreshAt: monitor.lastRefreshAt) {
                monitor.clearTarget(for: display)
            }
        }
    }
}
