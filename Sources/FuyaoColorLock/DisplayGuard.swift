import AppKit
import CoreGraphics
import Foundation

/// Watches display reconfiguration and wake events, then re-applies the pinned
/// connection color mode through the BetterDisplay CLI whenever the target
/// display drifts away from it.
@MainActor
final class DisplayGuard: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case locked(description: String)
        case recovered(description: String)
        case error(message: String)
        case disabled

        var isHealthy: Bool {
            switch self {
            case .locked, .recovered: return true
            default: return false
            }
        }

        var summary: String {
            switch self {
            case .idle: return String(localized: "Idle", comment: "phase idle")
            case .checking: return String(localized: "Checking…", comment: "phase checking")
            case .locked(let description): return description
            case .recovered(let description):
                return String(localized: "Re-applied \(description)", comment: "phase recovered")
            case .error(let message): return message
            case .disabled: return String(localized: "Lock disabled", comment: "phase disabled")
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastActionAt: Date?
    /// Names discovered from the CLI, refreshed on demand for the menu picker.
    @Published private(set) var availableDisplays: [String] = []

    private var debounceWorkItem: DispatchWorkItem?
    /// Reconfiguration callbacks arrive as a storm while a display link is
    /// re-negotiated; coalesce them.
    private let debounceInterval: TimeInterval = 2.5
    /// Safety net poll: catches resets that arrive without any observable
    /// event (driver renegotation, display-side power events).
    private let pollInterval: TimeInterval = 15
    private var pollTimer: Timer?

    init() {
        registerDisplayCallback()
        observeWorkspaceNotifications()
        refreshDisplayList()
        scheduleCheck(delay: 1.0)
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfQuiet()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// The poll skips itself while a check is already running.
    private func checkIfQuiet() {
        guard phase != .checking else { return }
        Task { @MainActor in
            await checkAndCorrect()
        }
    }

    // MARK: - Event sources

    private func registerDisplayCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
            guard let userInfo else { return }
            let guardObject = Unmanaged<DisplayGuard>.fromOpaque(userInfo).takeUnretainedValue()
            // Mode-level changes are included so a manual switch away from the
            // pinned mode is pulled back within the debounce window; the guard's
            // own corrections re-enter here as a no-op confirmation.
            let interesting: CGDisplayChangeSummaryFlags = [
                .addFlag, .removeFlag, .enabledFlag, .disabledFlag, .setModeFlag,
            ]
            guard !flags.intersection(interesting).isEmpty else { return }
            Task { @MainActor in
                guardObject.scheduleCheck()
            }
        }
        CGDisplayRegisterReconfigurationCallback(callback, context)
    }

    private func observeWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleCheck(delay: 3.0)
                }
            }
        }
    }

    // MARK: - Scheduling

    func scheduleCheck(delay: TimeInterval? = nil) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.checkAndCorrect()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (delay ?? debounceInterval), execute: work)
    }

    /// Manual "fix it now" from the menu.
    func applyNow() async {
        debounceWorkItem?.cancel()
        await checkAndCorrect()
    }

    // MARK: - Core logic

    func checkAndCorrect() async {
        guard Settings.isEnabled else {
            phase = .disabled
            return
        }
        guard !Settings.displayName.isEmpty else {
            phase = .error(message: String(localized: "No display selected", comment: "no target display"))
            return
        }
        guard BetterDisplayCLI.isAvailable else {
            phase = .error(message: BetterDisplayCLI.CLIError.notInstalled.localizedDescription)
            return
        }

        phase = .checking
        lastActionAt = Date()

        let displayName = Settings.displayName
        let preset = Settings.preset

        // CLI calls block; keep them off the main actor.
        let outcome = await Task.detached(priority: .userInitiated) { () throws -> Bool in
            let current = try BetterDisplayCLI.getConnectionModeDescription(displayName: displayName)
            if current.contains(preset.expectedFragment) {
                return false // already correct, nothing applied
            }
            try BetterDisplayCLI.setConnectionMode(preset, displayName: displayName)
            // The display link takes a moment to settle; verify with retries.
            for attempt in 0..<3 where attempt > 0 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let after = try BetterDisplayCLI.getConnectionModeDescription(displayName: displayName)
                if after.contains(preset.expectedFragment) {
                    return true
                }
            }
            throw BetterDisplayCLI.CLIError.failed(status: 0, stderr: String(
                format: String(localized: "Mode did not stick. Still: %@", comment: "mode mismatch after set"),
                current))
        }.result

        switch outcome {
        case .success(let applied):
            phase = applied ? .recovered(description: preset.title) : .locked(description: preset.title)
            lastActionAt = Date()
        case .failure(let error):
            phase = .error(message: error.localizedDescription)
        }
    }

    func refreshDisplayList() {
        let lookup = Task.detached(priority: .utility) {
            (try? BetterDisplayCLI.listDisplayNames()) ?? []
        }
        Task { @MainActor in
            let names = await lookup.value
            availableDisplays = names
            // Default the target to the first physical display once.
            if Settings.displayName.isEmpty, let first = names.first {
                Settings.displayName = first
            }
        }
    }
}
