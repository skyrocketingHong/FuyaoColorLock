import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let presentation = PanelPresentation()
    private let overrides = EDIDOverrideManager()
    private var monitor: DisplayGuard?
    private var presentedContext: DisplayOpenContext?

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
        let activation = ScreenActivationResolver.capture(event: NSApp.currentEvent,
                                                         fallbackScreen: statusItem?.button?.window?.screen)
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu(activation: activation)
        } else if popover.isShown {
            popover.performClose(nil)
            if !ScreenLocationPolicy.shouldCloseExistingPopover(current: presentedContext, incoming: activation.context) {
                showPanel(activation: activation)
            }
        } else {
            showPanel(activation: activation)
        }
    }

    @objc private func showPanelFromMenu(_ sender: NSMenuItem) {
        guard let origin = sender.representedObject as? MenuActivation else { return }
        showPanel(activation: origin.value)
    }

    private func showPanel(activation: ScreenActivation) {
        guard let button = statusItem?.button, let monitor else { return }
        presentedContext = activation.context
        presentation.beginPresentation(context: activation.context, displays: monitor.displays)
        let size = PanelLayout.size(visibleFrame: activation.visibleFrame ?? button.window?.screen?.visibleFrame)
        presentation.size = size

        // Recreate the transient hosting tree so a previously used screen or
        // display page cannot leave stale scroll/safe-area geometry behind.
        let controller = PanelHostingController(
            rootView: PanelContent(monitor: monitor, presentation: presentation, overrides: overrides) { [weak self] in
                self?.showAbout()
            }
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
        let frame = ScreenActivationResolver.currentVisibleFrame(for: presentedContext)
            ?? controller.view.window?.screen?.visibleFrame
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

    private func showContextMenu(activation: ScreenActivation) {
        guard let statusItem, let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = menu.addItem(withTitle: String(localized: "Open"), action: #selector(showPanelFromMenu(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = MenuActivation(activation)
        let about = menu.addItem(withTitle: String(localized: "About Fuyao Color Lock…"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
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

    @objc private func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Fuyao Color Lock"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: name])
    }

    private final class MenuActivation: NSObject {
        let value: ScreenActivation

        init(_ value: ScreenActivation) { self.value = value }
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
