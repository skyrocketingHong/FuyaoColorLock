import AppKit
import SwiftUI

@MainActor
final class PanelPresentation: ObservableObject {
    @Published var selectedDisplayID: String?
    @Published var size = PanelLayout.preferredSize
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let presentation = PanelPresentation()
    private let overrides = EDIDOverrideManager()
    private var monitor: DisplayGuard?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = DisplayGuard()
        popover.behavior = .transient
        popover.animates = false

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let description = String(localized: "Display connection information")
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: description)
            button.image?.isTemplate = true
            button.toolTip = "Fuyao Color Lock · \(description)"
            button.setAccessibilityLabel(description)
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        overrides.isBusy || DisplayMutationGate.isBusy ? .terminateCancel : .terminateNow
    }

    @objc private func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    @objc private func showPanel() {
        guard let button = statusItem?.button, let monitor else { return }
        let size = PanelLayout.size(visibleFrame: button.window?.screen?.visibleFrame)
        presentation.size = size

        // Recreate the transient hosting tree so a previously used screen or
        // display page cannot leave stale scroll/safe-area geometry behind.
        let controller = PanelHostingController(
            rootView: PanelContent(monitor: monitor, presentation: presentation, overrides: overrides)
        )
        popover.contentViewController = controller
        synchronizeCanvas(size, controller: controller)
        popover.appearance = NSApp.effectiveAppearance
        controller.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        controller.view.window?.makeKey()
    }

    @objc private func screenParametersChanged() {
        guard popover.isShown, let controller = popover.contentViewController else { return }
        let frame = controller.view.window?.screen?.visibleFrame
            ?? statusItem?.button?.window?.screen?.visibleFrame
        let size = PanelLayout.shrinking(popover.contentSize, toFit: frame)
        guard size != popover.contentSize else { return }
        presentation.size = size
        synchronizeCanvas(size, controller: controller)
    }

    private func synchronizeCanvas(_ size: CGSize, controller: NSViewController) {
        controller.preferredContentSize = size
        controller.view.setFrameSize(size)
        controller.view.setBoundsOrigin(.zero)
        controller.view.setBoundsSize(size)
        popover.contentSize = size
    }

    private func showContextMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = menu.addItem(withTitle: String(localized: "Open"), action: #selector(showPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: String(localized: "Quit"), action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = !overrides.isBusy && !DisplayMutationGate.isBusy
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class PanelHostingController: NSViewController {
    private let content: PanelHostingView

    init(rootView: PanelContent) {
        content = PanelHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        content.sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        view = content
    }
}

@MainActor
private final class PanelHostingView: NSHostingView<PanelContent> {
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { true }
}
