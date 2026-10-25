import AppKit
import CoreGraphics
import Foundation

enum ModeApplyResult: Equatable {
    case applying, confirmed, unconfirmed, unavailable, failed
}

@MainActor
final class DisplayGuard: ObservableObject {
    @Published private(set) var displays: [PhysicalDisplay] = []
    @Published private(set) var preferences: [String: DisplayPreference] = [:]
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var refreshFailed = false
    @Published private(set) var lastAction: String?
    @Published private(set) var isApplying = false
    @Published private(set) var applyResults: [String: ModeApplyResult] = [:]
    @Published private(set) var lockStates: [String: ModeLockState] = [:]

    private let backend: DisplayBackend
    private let defaults: UserDefaults
    private let automaticScheduling: Bool
    private var refreshTask: Task<Void, Never>?
    private var scheduledLockTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var confirmedModes: [String: NativeConnectionMode] = [:]
    private var targets: [String: ModeLockTarget] = [:]
    private var retries: [String: ModeLockRetry] = [:]
    private var revisions: [String: UInt64] = [:]
    private var applyingDisplayID: String?
    private var isReconciling = false
    private var isSleeping = false

    init(defaults: UserDefaults = .standard, backend: DisplayBackend? = nil, startObserving: Bool = true) {
        self.defaults = defaults
        self.backend = backend ?? .live
        automaticScheduling = startObserving
        if startObserving { _ = PrivateSLS.ensureConnection() }
        reload()
        if startObserving {
            observeDisplayNotifications()
            startPolling()
        }
    }

    func reload() {
        refreshCatalog()
        scheduleLockPass()
    }

    private func refreshCatalog() {
        switch backend.snapshot() {
        case .success(let snapshot):
            if displays != snapshot { displays = snapshot }
            let currentPreferences = Dictionary(uniqueKeysWithValues: snapshot.map {
                ($0.id, Settings.preference(for: $0, defaults: defaults))
            })
            if preferences != currentPreferences { preferences = currentPreferences }
            for display in snapshot {
                if let target = Settings.modeLockTarget(for: display.id, defaults: defaults) {
                    targets[display.id] = target
                } else {
                    targets.removeValue(forKey: display.id)
                }
            }
            for (identity, mode) in confirmedModes {
                if snapshot.first(where: { $0.id == identity })?.liveConnection?.currentMode != mode {
                    applyResults[identity] = .unconfirmed
                    confirmedModes.removeValue(forKey: identity)
                }
            }
            refreshFailed = false
            lastRefreshAt = backend.now()
        case .failure:
            displays = []
            preferences = [:]
            refreshFailed = true
            for identity in confirmedModes.keys { applyResults[identity] = .unconfirmed }
            confirmedModes.removeAll()
        }
        updateLockStates()
    }

    func preference(for display: PhysicalDisplay) -> DisplayPreference {
        preferences[display.id] ?? DisplayPreference()
    }

    func clearTarget(for display: PhysicalDisplay) {
        Settings.clearTarget(for: display, defaults: defaults)
        preferences[display.id] = DisplayPreference()
        lastAction = String(localized: "Historical target cleared. Display settings are unchanged.")
    }

    func lockState(for display: PhysicalDisplay) -> ModeLockState {
        lockStates[display.id] ?? ModeLockState()
    }

    func setModeLock(_ enabled: Bool, for display: PhysicalDisplay) {
        if enabled {
            guard !isApplying, !isSleeping, !DisplayMutationGate.isBusy else { return }
            refreshCatalog()
            guard let fresh = displays.first(where: { $0.id == display.id }), canCaptureTarget(for: fresh),
                  let mode = fresh.liveConnection?.currentMode else { return }
            saveTarget(ModeLockTarget(mode), for: fresh.id)
        } else {
            revisions[display.id, default: 0] += 1
            targets.removeValue(forKey: display.id)
            retries.removeValue(forKey: display.id)
            Settings.setModeLockTarget(nil, for: display.id, defaults: defaults)
        }
        updateLockStates()
        scheduleLockPass()
    }

    func retryModeLock(for display: PhysicalDisplay) {
        guard targets[display.id] != nil else { return }
        revisions[display.id, default: 0] += 1
        retries[display.id] = ModeLockRetry()
        reload()
    }

    func apply(_ mode: NativeConnectionMode, to display: PhysicalDisplay) async {
        guard !isApplying, !isSleeping, !DisplayMutationGate.isBusy else { return }
        let revision = revisions[display.id, default: 0]
        let wasLocked = targets[display.id] != nil
        let result = await performApply(mode, to: display)
        if wasLocked, targets[display.id] != nil, revisions[display.id, default: 0] == revision {
            if result == .confirmed {
                saveTarget(ModeLockTarget(mode), for: display.id)
            } else {
                // An uncertain manual change must not be immediately pulled
                // back to the old lock target behind the user's action.
                retries[display.id, default: ModeLockRetry()].pause()
            }
        }
        updateLockStates()
        scheduleLockPass()
    }

    /// Called by the scheduler and by deterministic tests with a fake backend.
    func reconcileModeLocks() async {
        guard !isReconciling, !isSleeping else { return }
        isReconciling = true
        defer {
            isReconciling = false
            updateLockStates()
            scheduleLockPass()
        }
        refreshCatalog()
        for display in displays {
            guard !isSleeping else { break }
            guard let target = targets[display.id], !retry(for: display.id).isPaused,
                  retry(for: display.id).delay(at: backend.now()) == 0 else { continue }
            guard !isApplying, !DisplayMutationGate.isBusy else { break }
            guard backend.identity(display.cgDirectDisplayID) == display.id else { continue }
            guard case .restore(let mode) = ModeLockDecision.evaluate(target: target, connection: display.liveConnection) else {
                continue
            }
            guard retries[display.id, default: ModeLockRetry()].allowsAttempt(at: backend.now()) else { continue }
            let revision = revisions[display.id, default: 0]
            let result = await performApply(mode, to: display, automatic: true)
            guard targets[display.id] == target, revisions[display.id, default: 0] == revision else { continue }
            if result == .confirmed {
                retries[display.id, default: ModeLockRetry()].confirmed()
            } else if !isSleeping,
                      let current = displays.first(where: { $0.id == display.id }),
                      backend.identity(current.cgDirectDisplayID) == display.id,
                      case .restore = ModeLockDecision.evaluate(target: target, connection: current.liveConnection) {
                retries[display.id, default: ModeLockRetry()].failed(at: backend.now())
            }
        }
    }

    func setSleeping(_ sleeping: Bool) {
        isSleeping = sleeping
        if sleeping {
            scheduledLockTask?.cancel()
            scheduledLockTask = nil
            refreshTask?.cancel()
        } else {
            scheduleRefresh(delay: 4)
        }
        updateLockStates()
    }

    private func performApply(_ mode: NativeConnectionMode, to display: PhysicalDisplay,
                              automatic: Bool = false) async -> ModeApplyResult {
        guard !isApplying, !isSleeping,
              let live = display.liveConnection, live.isWritable, DisplayMutationGate.begin() else {
            applyResults[display.id] = .unavailable
            return .unavailable
        }
        isApplying = true
        applyingDisplayID = display.id
        applyResults[display.id] = .applying
        confirmedModes.removeValue(forKey: display.id)
        updateLockStates()
        defer {
            isApplying = false
            applyingDisplayID = nil
            DisplayMutationGate.end()
            updateLockStates()
        }

        guard let fresh = try? backend.snapshot().get().first(where: {
            $0.id == display.id && $0.cgDirectDisplayID == display.cgDirectDisplayID
        }), fresh.liveConnection?.isWritable == true,
              fresh.liveConnection?.currentMode == live.currentMode,
              backend.identity(display.cgDirectDisplayID) == display.id else {
            return completeApply(.unavailable, mode: mode, displayID: display.id)
        }
        switch backend.requestApply(mode, display.cgDirectDisplayID, live.currentMode, display.id) {
        case .unavailable:
            return completeApply(.unavailable, mode: mode, displayID: display.id)
        case .alreadyCurrent:
            return completeApply(.confirmed, mode: mode, displayID: display.id)
        case .requested:
            if automatic { retries[display.id, default: ModeLockRetry()].recordAttempt(at: backend.now()) }
            break
        }

        var verifier = ModeReadbackVerifier(expected: mode)
        for _ in 0..<12 {
            do { try await backend.wait(500_000_000) }
            catch { return completeApply(.unconfirmed, mode: mode, displayID: display.id) }
            guard !isSleeping, backend.identity(display.cgDirectDisplayID) == display.id else {
                return completeApply(.unconfirmed, mode: mode, displayID: display.id)
            }
            if verifier.observe(backend.connection(display.cgDirectDisplayID)?.currentMode) {
                return completeApply(.confirmed, mode: mode, displayID: display.id)
            }
        }
        return completeApply(.unconfirmed, mode: mode, displayID: display.id)
    }

    private func completeApply(_ result: ModeApplyResult, mode: NativeConnectionMode, displayID: String) -> ModeApplyResult {
        if result == .confirmed { confirmedModes[displayID] = mode }
        applyResults[displayID] = result
        refreshCatalog()
        return applyResults[displayID] ?? result
    }

    private func saveTarget(_ target: ModeLockTarget, for displayID: String) {
        revisions[displayID, default: 0] += 1
        targets[displayID] = target
        retries[displayID] = ModeLockRetry()
        Settings.setModeLockTarget(target, for: displayID, defaults: defaults)
    }

    private func retry(for identity: String) -> ModeLockRetry { retries[identity] ?? ModeLockRetry() }

    private func canCaptureTarget(for display: PhysicalDisplay) -> Bool {
        guard !isApplying, !isSleeping, display.uuidString != nil,
              backend.identity(display.cgDirectDisplayID) == display.id,
              let live = display.liveConnection, live.isWritable, !live.currentMode.isVirtual else { return false }
        let target = ModeLockTarget(live.currentMode)
        return target.isValid && live.modes.filter(target.matches).count == 1
    }

    private func updateLockStates() {
        var states: [String: ModeLockState] = [:]
        for identity in Set(targets.keys).union(displays.map(\.id)) {
            let display = displays.first { $0.id == identity }
            let target = targets[identity]
            var state = ModeLockState(isEnabled: target != nil,
                canEnable: display.map(canCaptureTarget) ?? false, target: target)
            if let target {
                if isSleeping { state.phase = .sleeping }
                else if applyingDisplayID == identity { state.phase = .restoring }
                else if retry(for: identity).isPaused { state.phase = .paused }
                else if let display, backend.identity(display.cgDirectDisplayID) == identity {
                    switch ModeLockDecision.evaluate(target: target, connection: display.liveConnection) {
                    case .matching: state.phase = .matching
                    case .restore: state.phase = .retryScheduled
                    case .unavailable: state.phase = .unavailable
                    case .incompatible: state.phase = .incompatible
                    }
                } else { state.phase = display == nil ? .waitingForDisplay : .unavailable }
            }
            states[identity] = state
        }
        if lockStates != states { lockStates = states }
    }

    private func scheduleLockPass() {
        guard automaticScheduling else { return }
        scheduledLockTask?.cancel()
        scheduledLockTask = nil
        guard !isSleeping, !isReconciling, !isApplying else { return }
        let delays = displays.compactMap { display -> TimeInterval? in
            guard let target = targets[display.id], !retry(for: display.id).isPaused,
                  backend.identity(display.cgDirectDisplayID) == display.id,
                  case .restore = ModeLockDecision.evaluate(target: target, connection: display.liveConnection) else { return nil }
            return max(DisplayMutationGate.isBusy ? 1 : 0.25, retry(for: display.id).delay(at: backend.now()))
        }
        guard let delay = delays.min() else { return }
        scheduledLockTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduledLockTask = nil
            // The cancellable timer does not own an in-flight write/readback.
            // Turning a lock off cancels only work that has not been submitted.
            Task { [weak self] in await self?.reconcileModeLocks() }
        }
    }

    private func observeDisplayNotifications() {
        observe(NSApplication.didChangeScreenParametersNotification, on: .default, delay: 0.5)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(true) }
            }
            observers.append((center, token))
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(false) }
            }
            observers.append((center, token))
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, delay: TimeInterval) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh(delay: delay) }
        }
        observers.append((center, token))
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func scheduleRefresh(delay: TimeInterval) {
        guard automaticScheduling else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    deinit {
        refreshTask?.cancel()
        scheduledLockTask?.cancel()
        pollTimer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }
}
