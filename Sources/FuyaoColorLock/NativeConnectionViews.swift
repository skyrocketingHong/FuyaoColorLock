import SwiftUI

struct LiveModeInformation: View {
    let connection: LiveDisplayConnection?
    let applyResult: ModeApplyResult?

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            if let connection {
                NativeModeDescription(mode: connection.currentMode, showsTiming: true, isCurrent: true)
                    .help("Read from the active system display connection.")
            } else {
                Label("Live mode is unavailable", systemImage: "questionmark.circle")
                Text("The system did not expose a readable live connection mode. Driver tables below remain available for reference.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let applyResult {
                ModeApplicationResult(result: applyResult)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModeApplicationResult: View {
    let result: ModeApplyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Latest mode change")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: PanelMetrics.rowSpacing) {
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
                Text("The display may briefly go blank when applying a mode.")
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
                        showsTiming: false,
                        isCurrent: mode == connection.currentMode,
                        canApply: connection.isWritable && mode.id != connection.currentMode.id,
                        isBusy: isBusy,
                        applyMode: applyMode
                    )
                    if mode.id != compatible.last?.id { Divider() }
                }
            }

            if !other.isEmpty {
                DisclosureGroup("Other modes (view only)") {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(other) { mode in
                            NativeModeRow(
                                mode: mode,
                                showsTiming: true,
                                isCurrent: mode == connection.currentMode,
                                canApply: false,
                                isBusy: isBusy,
                                applyMode: applyMode
                            )
                            if mode.id != other.last?.id { Divider() }
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}

private struct NativeModeRow: View {
    let mode: NativeConnectionMode
    let showsTiming: Bool
    let isCurrent: Bool
    let canApply: Bool
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        PanelControlRow(minimumLabelWidth: 180) {
            NativeModeDescription(mode: mode, showsTiming: showsTiming, isCurrent: isCurrent)
                .foregroundStyle(canApply || isCurrent ? .primary : .secondary)
        } control: {
            NativeModeAction(mode: mode, isCurrent: isCurrent, canApply: canApply,
                             isBusy: isBusy, applyMode: applyMode)
        }
        .padding(.vertical, 6)
        .frame(minHeight: PanelMetrics.modeRowMinHeight)
    }
}

private struct NativeModeDescription: View {
    let mode: NativeConnectionMode
    let showsTiming: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mode.formatLabel)
                .font(.callout.monospaced().weight(isCurrent ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            Text(parameters)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsTiming {
                Text(mode.timingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parameters: String {
        let gamut = mode.colorGamut == "gamut_SRGB" ? "sRGB" : mode.colorGamut
        return "\(mode.bitDepth)-bit · \(mode.hdrMode) · \(gamut)"
    }
}

private struct NativeModeAction: View {
    let mode: NativeConnectionMode
    let isCurrent: Bool
    let canApply: Bool
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        Group {
            if isCurrent {
                Text("Current")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if canApply {
                Button {
                    Task { await applyMode(mode) }
                } label: {
                    PanelActionLabel("Apply")
                }
                .modifier(PanelActionStyle())
                .disabled(isBusy)
                .accessibilityLabel(Text("Apply \(mode.title)", comment: "Apply button; the variable is the full connection format description."))
            } else {
                Text("View only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: PanelMetrics.actionColumnMinWidth, alignment: .trailing)
    }
}
