import SwiftUI

struct ModeLockView: View {
    let state: ModeLockState
    let isBusy: Bool
    let setEnabled: (Bool) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            PanelControlRow {
                Text("Lock color mode")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } control: {
                Toggle("Lock color mode", isOn: Binding(
                    get: { state.isEnabled },
                    set: setEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!state.isEnabled && (!state.canEnable || isBusy))
            }
            .help("Keep the current mode after wake or reconnection. Confirmed manual changes update the locked target.")

            if let message = statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.isEnabled, state.phase != .matching, let target = state.target {
                DisclosureGroup("Locked target") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.title).font(.callout.monospaced())
                        Text(target.timingLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.callout)
            }

            if state.phase == .paused || state.phase == .retryScheduled {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: retry) { PanelActionLabel("Retry") }
                        .modifier(PanelActionStyle())
                        .disabled(isBusy)
                        .help("Retry mode lock")
                        .accessibilityLabel("Retry mode lock")
                }
            }
        }
    }

    private var statusMessage: LocalizedStringKey? {
        switch state.phase {
        case .off:
            return !state.canEnable && !isBusy ? "Lock unavailable. Refresh to check again." : nil
        // The live-mode summary already owns in-flight and readback feedback.
        case .matching, .restoring: return nil
        case .waitingForDisplay: return "Waiting for the display to reconnect."
        case .unavailable: return "Locked mode unavailable. Refresh or choose another mode."
        case .incompatible: return "Timing changed. Choose a new mode to lock."
        case .retryScheduled: return "Waiting to restore the locked mode…"
        case .paused: return "Restoration paused. Check the connection, then retry."
        case .sleeping: return "Display asleep."
        case .waking: return "Waiting for the display and session…"
        }
    }
}
