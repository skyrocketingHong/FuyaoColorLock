import SwiftUI

struct EDIDSettingsView: View {
    let display: PhysicalDisplay
    @ObservedObject var manager: EDIDOverrideManager
    let lastRefreshAt: Date?
    @State private var status: EDIDOverrideStatus?

    var body: some View {
        InformationGroup("Prefer RGB with EDID override") {
            if let status {
                EDIDInstallationStatus(status: status)

                if let patch = status.patch, patch.hasChanges, !status.installed {
                    EDIDChangePreview(patch: patch)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PanelMetrics.rowSpacing) {
                        EDIDActionButtons(display: display, manager: manager, status: status)
                    }
                    VStack(spacing: PanelMetrics.rowSpacing) {
                        EDIDActionButtons(display: display, manager: manager, status: status)
                    }
                }
                .disabled(manager.isBusy)
            }

            Text("Full Range is not guaranteed. Installing or restoring requires administrator approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            EDIDDetails(path: status?.destinationPath)

            if manager.isBusy {
                HStack(spacing: PanelMetrics.rowSpacing) {
                    ProgressView().controlSize(.small)
                    Text("Working on the override…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

private struct EDIDChangePreview: View {
    let patch: EDIDPatch

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                EDIDChangeCount(title: "CTA flag groups", count: patch.clearedCTAFlags)
                EDIDChangeCount(title: "4:2:0 blocks", count: patch.removed420Blocks)
            }
            VStack(alignment: .leading, spacing: 4) {
                EDIDChangeCount(title: "CTA flag groups", count: patch.clearedCTAFlags)
                EDIDChangeCount(title: "4:2:0 blocks", count: patch.removed420Blocks)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct EDIDChangeCount: View {
    let title: LocalizedStringKey
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

private struct EDIDDetails: View {
    let path: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            DisclosureGroup("Override details") {
                Text("Removes CTA-advertised YCbCr support. Reconnect the display after installation or restoration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            if let path {
                DisclosureGroup("File location") {
                    Text(path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
        .font(.caption)
    }
}

private struct EDIDInstallationStatus: View {
    let status: EDIDOverrideStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.hasConflictingInstall {
                Label("An existing override needs review", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Text("The override or its backup record needs review before installation or restoration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if status.installed {
                Label("Override file installed", systemImage: "doc.badge.gearshape")
                    .font(.callout.weight(.medium))
                Text("Reconnect the display to load this configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if status.canRestore {
                Text("A previous operation needs restoration. Restore the backup state before installing again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let reason = status.unavailableReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let patch = status.patch, !patch.hasChanges {
                Text("No removable YCbCr advertisement was found. An override would not change this EDID.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready to export or install.")
                    .font(.callout)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EDIDActionButtons: View {
    let display: PhysicalDisplay
    @ObservedObject var manager: EDIDOverrideManager
    let status: EDIDOverrideStatus

    var body: some View {
        Group {
            Button {
                manager.exportOverride(for: display)
            } label: {
                PanelActionLabel("Export…")
                    .frame(maxWidth: .infinity)
            }
            .disabled(status.patch?.hasChanges != true)
            .help("Save the override file without installing it.")

            Button {
                manager.install(for: display)
            } label: {
                PanelActionLabel("Install…")
                    .frame(maxWidth: .infinity)
            }
            .disabled(status.patch?.hasChanges != true || status.installed || status.canRestore || status.hasConflictingInstall)
            .help("Install an RGB preference override with administrator approval.")

            Button {
                manager.restore(for: display)
            } label: {
                PanelActionLabel("Restore…")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!status.canRestore)
            .help("Restore the original override backed up by this app.")
        }
        .modifier(PanelActionStyle())
    }
}
