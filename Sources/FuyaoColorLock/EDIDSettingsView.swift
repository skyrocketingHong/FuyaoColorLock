import SwiftUI

struct EDIDSettingsView: View {
    let display: PhysicalDisplay
    @ObservedObject var manager: EDIDOverrideManager
    let lastRefreshAt: Date?
    @State private var status: EDIDOverrideStatus?

    var body: some View {
        InformationGroup("Installation configuration") {
            if let status {
                EDIDActionRow(display: display, manager: manager, status: status)
                    .disabled(manager.isBusy)
                EDIDInstallationStatus(status: status)
            }

            Text("Full Range is not guaranteed. Install and restore require administrator approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            EDIDDetails(status: status, isBusy: manager.isBusy) {
                manager.exportOverride(for: display)
            }

            if manager.isBusy {
                HStack(spacing: PanelMetrics.rowSpacing) {
                    ProgressView().controlSize(.small)
                    Text("Updating configuration…").font(.callout)
                }
            }

            if manager.resultDisplayID == display.id, let message = manager.lastMessage {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshStatus)
        .onPanelChange(of: display.id, perform: refreshStatus)
        .onPanelChange(of: lastRefreshAt, perform: refreshStatus)
        .onPanelChange(of: manager.isBusy) {
            if !manager.isBusy { refreshStatus() }
        }
        .modifier(PanelErrorAlert(title: "EDID override could not be completed", message: Binding(
            get: { manager.resultDisplayID == display.id ? manager.lastError : nil },
            set: { if $0 == nil { manager.dismissError() } }
        )))
    }

    private func refreshStatus() {
        status = manager.status(for: display)
    }
}

private struct EDIDActionRow: View {
    let display: PhysicalDisplay
    @ObservedObject var manager: EDIDOverrideManager
    let status: EDIDOverrideStatus

    var body: some View {
        PanelControlRow(minimumLabelWidth: 120) {
            Text("Prefer RGB")
                .fixedSize(horizontal: false, vertical: true)
        } control: {
            HStack(spacing: PanelMetrics.rowSpacing) {
                if status.installed || status.canRestore {
                    Button {
                        manager.restore(for: display)
                    } label: {
                        PanelActionLabel("Restore…")
                    }
                    .modifier(PanelActionStyle())
                    .disabled(!status.canRestore)
                    .help("Restore the original override backed up by this app.")
                } else {
                    Button {
                        manager.install(for: display)
                    } label: {
                        PanelActionLabel("Install…")
                    }
                    .modifier(PanelActionStyle())
                    .disabled(status.patch?.hasChanges != true || status.hasConflictingInstall)
                    .help("Install an RGB preference override with administrator approval.")
                }
            }
        }
    }
}

private struct EDIDDetails: View {
    let status: EDIDOverrideStatus?
    let isBusy: Bool
    let export: () -> Void

    var body: some View {
        DisclosureGroup("Configuration details") {
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                Text("Removes CTA-advertised YCbCr support. Reconnect the display after installation or restoration.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let patch = status?.patch, patch.hasChanges, status?.installed != true {
                    LabeledContent("CTA flag groups") {
                        Text(patch.clearedCTAFlags, format: .number).monospacedDigit()
                    }
                    LabeledContent("4:2:0 blocks") {
                        Text(patch.removed420Blocks, format: .number).monospacedDigit()
                    }
                }
                if let path = status?.destinationPath {
                    Text("File location").foregroundStyle(.secondary)
                    Text(path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(action: export) { PanelActionLabel("Export…") }
                        .modifier(PanelActionStyle())
                        .disabled(isBusy || status?.patch?.hasChanges != true)
                        .help("Save the override file without installing it.")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .font(.callout)
    }
}

private struct EDIDInstallationStatus: View {
    let status: EDIDOverrideStatus

    var body: some View {
        Group {
            if status.hasConflictingInstall {
                Label("Review the installed file and backup before retrying.", systemImage: "exclamationmark.triangle")
            } else if status.installed {
                Label("Installed. Reconnect the display to load it.", systemImage: "doc.badge.gearshape")
            } else if status.canRestore {
                Text("Restore the previous configuration before reinstalling.")
            } else if let reason = status.unavailableReason {
                Text(reason)
            } else if let patch = status.patch, !patch.hasChanges {
                Text("No EDID changes are available.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
