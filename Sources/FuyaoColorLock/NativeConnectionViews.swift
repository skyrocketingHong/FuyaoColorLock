import SwiftUI

struct LiveModeInformation: View {
    let connection: LiveDisplayConnection?
    let applyResult: ModeApplyResult?

    var body: some View {
        InformationGroup("Live connection mode") {
            if let connection {
                Text(connection.currentMode.title)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connection.currentMode.timingLabel)
                    .font(.callout.monospacedDigit())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Text("Read from the active system display connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Live mode is unavailable", systemImage: "questionmark.circle")
                Text("The system did not expose a readable live connection mode. Driver tables below remain available for reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let applyResult {
                ModeApplicationResult(result: applyResult)
            }
        }
    }
}

private struct ModeApplicationResult: View {
    let result: ModeApplyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Latest mode change")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                if result == .applying {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: result == .confirmed ? "checkmark.circle" : "exclamationmark.triangle")
                        .accessibilityHidden(true)
                }
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        switch result {
        case .applying:
            return "Requesting the mode change and checking the system response…"
        case .confirmed:
            return "System read-back matched the requested mode after the change."
        case .unconfirmed:
            return "The selected mode has not been confirmed. Check the live mode above before retrying."
        case .unavailable:
            return "This mode cannot be applied to the current connection. Refresh to read the available modes."
        case .failed:
            return "The mode change could not be completed. Check the live connection before retrying."
        }
    }
}

struct NativeModeInformation: View {
    let connection: LiveDisplayConnection
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        let compatible = connection.compatibleModes
        let other = connection.otherModes
        return InformationGroup("Connection mode options") {
            if connection.isWritable {
                Text("Apply a format compatible with the current timing. The display may briefly go blank while the connection changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("View only · Applying modes is unavailable", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if compatible.isEmpty {
                Text("No compatible mode changes are available for this timing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(compatible) { mode in
                    NativeModeRow(
                        mode: mode,
                        isCurrent: mode == connection.currentMode,
                        canApply: connection.isWritable && mode.id != connection.currentMode.id,
                        isBusy: isBusy,
                        applyMode: applyMode
                    )
                    if mode.id != compatible.last?.id { Divider() }
                }
            }

            if !other.isEmpty {
                DisclosureGroup("Other timings (view only)") {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(other) { mode in
                            NativeModeRow(
                                mode: mode,
                                isCurrent: mode == connection.currentMode,
                                canApply: false,
                                isBusy: isBusy,
                                applyMode: applyMode
                            )
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

}

private struct NativeModeRow: View {
    let mode: NativeConnectionMode
    let isCurrent: Bool
    let canApply: Bool
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.callout.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(mode.timingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(canApply || isCurrent ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCurrent {
                Text("Current")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if canApply {
                Button("Apply") {
                    Task { await applyMode(mode) }
                }
                .modifier(PanelActionStyle())
                .disabled(isBusy)
                .accessibilityLabel(Text("Apply \(mode.title)", comment: "Apply button; the variable is the full connection format description."))
            } else {
                Text("View only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
