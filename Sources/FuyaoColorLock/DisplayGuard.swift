import AppKit
import CoreGraphics
import Foundation

enum ModeApplyResult: Equatable {
    case applying
    case confirmed
    case unconfirmed
    case unavailable
    case failed
}

/// Refreshes driver tables and recorded configuration without reprogramming a link.
@MainActor
final class DisplayGuard: ObservableObject {
    @Published private(set) var displays: [PhysicalDisplay] = []
    @Published private(set) var preferences: [String: DisplayPreference] = [:]
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var refreshFailed = false
    @Published private(set) var lastAction: String?
    @Published private(set) var isApplying = false
    @Published private(set) var applyResults: [String: ModeApplyResult] = [:]

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var confirmedModes: [String: NativeConnectionMode] = [:]

    init() {
        _ = PrivateSLS.ensureConnection()
        reload()
        observeDisplayNotifications()
        startPolling()
    }

    func reload() {
        switch DisplayCatalog.snapshotResult() {
        case .success(let snapshot):
            if displays != snapshot { displays = snapshot }
            let currentPreferences = Dictionary(uniqueKeysWithValues: snapshot.map {
                ($0.id, Settings.preference(for: $0))
            })
            if preferences != currentPreferences { preferences = currentPreferences }
            for (identity, mode) in confirmedModes {
                if snapshot.first(where: { $0.id == identity })?.liveConnection?.currentMode != mode {
                    applyResults[identity] = .unconfirmed
                    confirmedModes.removeValue(forKey: identity)
                }
            }
            refreshFailed = false
            lastRefreshAt = Date()
        case .failure:
            // Do not present a retained successful snapshot as a fresh reading.
            displays = []
            preferences = [:]
            refreshFailed = true
            for identity in confirmedModes.keys { applyResults[identity] = .unconfirmed }
            confirmedModes.removeAll()
        }
    }

    func preference(for display: PhysicalDisplay) -> DisplayPreference {
        preferences[display.id] ?? DisplayPreference()
    }

    func clearTarget(for display: PhysicalDisplay) {
        Settings.clearTarget(for: display)
        preferences[display.id] = DisplayPreference()
        lastAction = String(localized: "Historical target cleared. Display settings are unchanged.")
    }

    func apply(_ mode: NativeConnectionMode, to display: PhysicalDisplay) async {
        guard !isApplying else { return }
        guard let live = display.liveConnection, live.isWritable, DisplayMutationGate.begin() else {
            applyResults[display.id] = .unavailable
            return
        }
        isApplying = true
        applyResults[display.id] = .applying
        confirmedModes.removeValue(forKey: display.id)
        defer {
            isApplying = false
            DisplayMutationGate.end()
        }

        guard let fresh = try? DisplayCatalog.snapshotResult().get().first(where: {
            $0.id == display.id && $0.cgDirectDisplayID == display.cgDirectDisplayID
        }), fresh.liveConnection?.isWritable == true,
              fresh.liveConnection?.currentMode == live.currentMode else {
            applyResults[display.id] = .unavailable
            reload()
            return
        }

        switch CoreDisplayModes.requestApply(mode, to: display.cgDirectDisplayID, expectedCurrent: live.currentMode,
                                             expectedDisplayIdentity: display.id) {
        case .unavailable:
            applyResults[display.id] = .unavailable
            reload()
            return
        case .alreadyCurrent:
            confirmedModes[display.id] = mode
            applyResults[display.id] = .confirmed
            reload()
            return
        case .requested:
            break
        }

        var verifier = ModeReadbackVerifier(expected: mode)
        for _ in 0..<12 {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                applyResults[display.id] = .unconfirmed
                reload()
                return
            }
            guard DisplayCatalog.stableIdentity(for: display.cgDirectDisplayID) == display.id else {
                applyResults[display.id] = .unconfirmed
                reload()
                return
            }
            let actual = CoreDisplayModes.snapshot(for: display.cgDirectDisplayID)?.currentMode
            if verifier.observe(actual) {
                confirmedModes[display.id] = mode
                applyResults[display.id] = .confirmed
                reload()
                return
            }
        }
        reload()
        applyResults[display.id] = .unconfirmed
    }

    private func observeDisplayNotifications() {
        observe(NSApplication.didChangeScreenParametersNotification, on: .default, delay: 0.5)
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observe(name, on: NSWorkspace.shared.notificationCenter, delay: 4.0)
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, delay: TimeInterval) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh(delay: delay) }
        }
        observers.append((center, token))
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

    private func scheduleRefresh(delay: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    deinit {
        refreshTask?.cancel()
        pollTimer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }
}
