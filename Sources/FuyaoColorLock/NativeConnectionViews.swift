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
                Label("Live mode unavailable. Refresh to check again.", systemImage: "questionmark.circle")
                    .font(.callout)
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
        HStack(alignment: .top, spacing: PanelMetrics.rowSpacing) {
            if result == .applying {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: result == .confirmed ? "checkmark.circle" : "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        switch result {
        case .applying: return "Applying and verifying…"
        case .confirmed: return "Confirmed by system read-back."
        case .unconfirmed: return "Not confirmed. Refresh and try again."
        case .unavailable: return "Mode unavailable. Refresh to check again."
        case .failed: return "Couldn't switch modes. Refresh and try again."
        }
    }
}

struct NativeModeInformation: View {
    let connection: LiveDisplayConnection
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        let alternatives = connection.compatibleModes.filter { $0 != connection.currentMode }
        let other = connection.otherModes.filter { $0 != connection.currentMode }
        return VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            if !connection.isWritable {
                Label("Mode changes unavailable. Refresh to check again.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !alternatives.isEmpty {
                InformationGroup("Switch mode") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(alternatives) { mode in
                            NativeModeRow(mode: mode, showsTiming: false,
                                canApply: connection.isWritable && mode.id != connection.currentMode.id,
                                isBusy: isBusy, applyMode: applyMode)
                            if mode.id != alternatives.last?.id { Divider() }
                        }
                    }
                }
            }

            if !other.isEmpty {
                DisclosureGroup("Other modes (view only)") {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(other) { mode in
                            NativeModeRow(mode: mode, showsTiming: true,
                                canApply: false, isBusy: isBusy, applyMode: applyMode)
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
    let canApply: Bool
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        Group {
            if canApply {
                PanelControlRow(minimumLabelWidth: 180) {
                    NativeModeDescription(mode: mode, showsTiming: showsTiming, isCurrent: false)
                } control: {
                    NativeModeAction(mode: mode, isBusy: isBusy, applyMode: applyMode)
                }
            } else {
                NativeModeDescription(mode: mode, showsTiming: showsTiming, isCurrent: false)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("View only")
            }
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
    let isBusy: Bool
    let applyMode: (NativeConnectionMode) async -> Void

    var body: some View {
        Button {
            Task { await applyMode(mode) }
        } label: {
            PanelActionLabel("Apply")
        }
        .modifier(PanelActionStyle())
        .disabled(isBusy)
        .help("The display may briefly go blank when applying a mode.")
        .accessibilityLabel(Text("Apply \(mode.title)", comment: "Apply button; the variable is the full connection format description."))
        .frame(minWidth: PanelMetrics.actionColumnMinWidth, alignment: .trailing)
    }
}
