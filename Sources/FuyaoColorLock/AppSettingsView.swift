import AppKit
import ServiceManagement
import SwiftUI

struct AppSettingsView: View {
    let showAbout: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelSectionTitle(title: "Application settings")
            InformationGroup("Startup") {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: updateLoginItem))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if needsApproval {
                    Button("Allow in Login Items…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .modifier(PanelActionStyle())
                }
            }
            AboutInformation(showAbout: showAbout)
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

private struct AboutInformation: View {
    let showAbout: () -> Void

    var body: some View {
        InformationGroup("About") {
            LabeledContent("Version") {
                Text(version)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }
            Button("About Fuyao Color Lock…", action: showAbout)
                .modifier(PanelActionStyle())
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? String(localized: "Unavailable")
        let build = info["CFBundleVersion"] as? String ?? String(localized: "Unavailable")
        return "\(version) (\(build))"
    }
}
