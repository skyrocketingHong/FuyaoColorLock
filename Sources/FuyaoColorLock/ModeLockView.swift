import SwiftUI

struct ModeLockView: View {
    let state: ModeLockState
    let isBusy: Bool
    let setEnabled: (Bool) -> Void
    let retry: () -> Void

    var body: some View {
        InformationGroup("Mode lock") {
            Toggle("Lock color mode", isOn: Binding(
                get: { state.isEnabled },
                set: setEnabled
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!state.isEnabled && (!state.canEnable || isBusy))

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.isEnabled, let target = state.target {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Locked target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(target.title)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(target.timingLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if state.phase == .restoring {
                ProgressView().controlSize(.small)
            }
            if state.phase == .paused || state.phase == .retryScheduled {
                Button("Retry mode lock", action: retry)
                    .modifier(PanelActionStyle())
                    .disabled(isBusy)
            }
        }
    }

    private var statusMessage: LocalizedStringKey {
        switch state.phase {
        case .off:
            return state.canEnable
                ? "Keep the current mode after wake or reconnection. Confirmed manual changes update the locked target."
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
        }
    }
}
