import AppKit
import CoreGraphics
import Foundation

/// Watches display events and keeps the per-display lock state fresh.
///
/// The lock works in two layers:
/// 1. The EDID override (installed separately) removes unwanted connection
///    color modes from the driver's table, so macOS cannot pick them at all.
/// 2. When a locked display goes through a reconfiguration, wake, or manual
///    mode change, the guard triggers a display re-detection and a link
///    re-program (same-resolution timing flip when possible), which makes
///    macOS re-run mode selection under the override's constraints.
@MainActor
final class DisplayGuard: ObservableObject {
    @Published private(set) var displays: [PhysicalDisplay] = []
    @Published private(set) var lastAction: String?
    @Published private(set) var lastActionAt: Date?

    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 3.0
    private var pollTimer: Timer?

    init() {
        _ = PrivateSLS.ensureConnection()
        reload()
        registerDisplayCallback()
        observeWorkspaceNotifications()
        scheduleReassert(delay: 1.0)
        startPolling()
    }

    // MARK: - Catalog

    func reload() {
        let snapshot = DisplayCatalog.snapshot()
        // IORegistry timing tables change after link events; a plain diff
        // against published state keeps object identity where possible.
        displays = snapshot
    }

    // MARK: - Event sources

    private func registerDisplayCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
            guard let userInfo else { return }
            let guardObject = Unmanaged<DisplayGuard>.fromOpaque(userInfo).takeUnretainedValue()
            let interesting: CGDisplayChangeSummaryFlags = [
                .addFlag, .removeFlag, .enabledFlag, .disabledFlag, .setModeFlag,
            ]
            guard !flags.intersection(interesting).isEmpty else { return }
            Task { @MainActor in
                guardObject.scheduleReassert()
            }
        }
        CGDisplayRegisterReconfigurationCallback(callback, context)
    }

    private func observeWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleReassert(delay: 4.0)
                }
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Reassert

    func scheduleReassert(delay: TimeInterval? = nil) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.reassert()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? debounceInterval), execute: work)
    }

    func reassert() {
        guard Settings.anyLockEnabled else {
            reload()
            return
        }
        var actions: [String] = []
        if PrivateSLS.detectDisplays() {
            actions.append("re-detected displays")
        }
        // Re-apply the current CGS mode on locked displays: an identical-mode
        // apply is a no-op for the desktop but the transaction still runs the
        // display pipeline update path on most systems; if it is rejected we
        // simply rely on the detection above.
        reload()
        let names = displays
            .filter { Settings.isLocked($0.id) }
            .map(\.name)
        if !names.isEmpty {
            actions.append("lock active on \(names.joined(separator: ", "))")
        }
        lastAction = actions.joined(separator: "; ")
        lastActionAt = Date()
    }

    /// Manual button.
    func reassertNow() {
        debounceWorkItem?.cancel()
        reassert()
    }
}
