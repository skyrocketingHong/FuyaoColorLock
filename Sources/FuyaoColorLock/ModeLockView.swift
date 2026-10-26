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

            HStack(alignment: .top, spacing: PanelMetrics.rowSpacing) {
                if state.phase == .restoring {
                    ProgressView().controlSize(.small)
                }
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help("Keep the current mode after wake or reconnection. Confirmed manual changes update the locked target.")

            if state.isEnabled, let target = state.target {
                DisclosureGroup("Locked target") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.title)
                            .font(.callout.monospaced())
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
                    Button(action: retry) {
                        PanelActionLabel("Retry")
                    }
                    .modifier(PanelActionStyle())
                    .disabled(isBusy)
                    .help("Retry mode lock")
                    .accessibilityLabel("Retry mode lock")
                }
            }
        }
    }

    private var statusMessage: LocalizedStringKey {
        switch state.phase {
        case .off:
            return state.canEnable
                ? "Keep this mode after wake or reconnection."
                : "A readable, supported native mode is required before locking."
        case .matching:
            return "Lock enabled. The system mode matches the saved target."
        case .restoring:
            return "Restoring the locked mode and checking system read-back…"
        case .waitingForDisplay:
            return "Waiting for the display to reconnect before restoring its locked mode."
        case .unavailable:
            return "The locked mode is currently unavailable. No change will be made."
        case .incompatible:
            return "The current timing is incompatible with the saved target. Lock restoration is waiting."
        case .retryScheduled:
            return "The locked mode was not confirmed. Another attempt is scheduled."
        case .paused:
            return "Automatic attempts are paused. Check the connection, then retry or turn off the lock."
        case .sleeping:
            return "The display is sleeping. Restoration resumes after wake."
        case .waking:
            return "Waiting for the display and user session to become ready."
        }
    }
}
