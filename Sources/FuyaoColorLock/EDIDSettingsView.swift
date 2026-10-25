import SwiftUI

struct EDIDSettingsView: View {
    let display: PhysicalDisplay
    @ObservedObject var manager: EDIDOverrideManager
    let lastRefreshAt: Date?
    @State private var status: EDIDOverrideStatus?

    var body: some View {
        InformationGroup("Prefer RGB with EDID override") {
            Text("Remove advertised YCbCr support to favor RGB. Full Range is not guaranteed; reconnect the display and verify its output after installation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status {
                EDIDInstallationStatus(status: status)

                if let patch = status.patch, patch.hasChanges, !status.installed {
                    EDIDChangePreview(patch: patch)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        EDIDActionButtons(display: display, manager: manager, status: status)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        EDIDActionButtons(display: display, manager: manager, status: status)
                    }
                }
                .disabled(manager.isBusy)

                if let path = status.destinationPath {
                    DisclosureGroup("File location") {
                        Text(path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }

            if manager.isBusy {
                HStack(spacing: 8) {
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
        .onChange(of: display.id) { _ in refreshStatus() }
        .onChange(of: lastRefreshAt) { _ in refreshStatus() }
        .onChange(of: manager.isBusy) { busy in
            if !busy { refreshStatus() }
        }
        .alert("EDID override could not be completed", isPresented: Binding(
            get: { manager.resultDisplayID == display.id && manager.lastError != nil },
            set: { if !$0 { manager.dismissError() } }
        )) {
            Button("OK", role: .cancel) { manager.dismissError() }
        } message: {
            Text(manager.lastError ?? "")
        }
    }

    private func refreshStatus() {
        status = manager.status(for: display)
    }
}

private struct EDIDChangePreview: View {
    let patch: EDIDPatch

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("CTA flag groups to clear")
                Spacer(minLength: 8)
                Text(patch.clearedCTAFlags, format: .number).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("YCbCr 4:2:0 blocks to remove")
                Spacer(minLength: 8)
                Text(patch.removed420Blocks, format: .number).monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EDIDInstallationStatus: View {
    let status: EDIDOverrideStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status.hasConflictingInstall {
                Label("An existing override needs review", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Text("The override or its backup record needs review before installation or restoration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if status.installed {
                Label("Override file installed", systemImage: "doc.badge.gearshape")
                    .font(.callout.weight(.medium))
                Text("Reconnect to load it. Installation does not verify RGB or Full Range output.")
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
                Text("Ready to export or install. Installation requires administrator approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        Button("Export…") { manager.exportOverride(for: display) }
            .disabled(status.patch?.hasChanges != true)
            .help("Save the override file without installing it.")
        Button("Install…") { manager.install(for: display) }
            .disabled(status.patch?.hasChanges != true || status.installed || status.canRestore || status.hasConflictingInstall)
            .help("Install an RGB preference override with administrator approval.")
        Button("Restore…") { manager.restore(for: display) }
            .disabled(!status.canRestore)
            .help("Restore the original override backed up by this app.")
    }
}
