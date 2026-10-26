import AppKit
import ServiceManagement
import SwiftUI

struct AppSettingsView: View {
    let showAbout: () -> Void
    let isBusy: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            PanelSectionTitle(title: "Application settings")
            GroupBox {
                VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                    LoginItemSettingsRow(
                        isEnabled: Binding(get: { launchAtLogin }, set: updateLoginItem),
                        needsApproval: needsApproval
                    )
                    Divider()
                    AboutInformation(showAbout: showAbout, isBusy: isBusy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: refreshLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        .modifier(PanelErrorAlert(title: "Login item could not be changed", message: $loginError))
    }

    private func refreshLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }
}

private struct LoginItemSettingsRow: View {
    @Binding var isEnabled: Bool
    let needsApproval: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            PanelControlRow {
                Text("Launch at Login")
                    .fixedSize(horizontal: false, vertical: true)
            } control: {
                Toggle("Launch at Login", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .accessibilityLabel("Launch at Login")
            }
            if needsApproval {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        SMAppService.openSystemSettingsLoginItems()
                    } label: {
                        PanelActionLabel("Allow in Login Items…")
                    }
                    .modifier(PanelActionStyle())
                }
            }
        }
    }
}

private struct AboutInformation: View {
    let showAbout: () -> Void
    let isBusy: Bool

    var body: some View {
        PanelControlRow {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Version")
                Text(version)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        } control: {
            HStack(spacing: PanelMetrics.rowSpacing) {
                Button(action: showAbout) { PanelActionLabel("About…") }
                    .modifier(PanelActionStyle())
                    .accessibilityLabel("About Fuyao Color Lock…")
                Button { NSApp.terminate(nil) } label: { PanelActionLabel("Quit", minimumWidth: 44) }
                    .modifier(PanelActionStyle())
                    .keyboardShortcut("q")
                    .disabled(isBusy)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? String(localized: "Unavailable")
        let build = info["CFBundleVersion"] as? String ?? String(localized: "Unavailable")
        return "\(version) (\(build))"
    }
}
