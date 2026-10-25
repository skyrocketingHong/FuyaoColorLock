import SwiftUI

@main
struct FuyaoColorLockApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBarController

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
    }
}
