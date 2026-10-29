import AppKit
import CoreGraphics
import Foundation
import os

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
    private var wakeCheckTask: Task<Void, Never>?
    private var lockMonitorTask: Task<Void, Never>?
    private var scheduledLockAt: Date?
    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var displayCallbackRegistered = false
    private var confirmedModes: [String: NativeConnectionMode] = [:]
    private var targets: [String: ModeLockTarget] = [:]
    private var retries: [String: ModeLockRetry] = [:]
    private var revisions: [String: UInt64] = [:]
    private var applyingDisplayID: String?
    private var isReconciling = false
    private var wakeState = DisplayWakeState()
    private var displayWakeStates: [String: DisplayWakeState] = [:]
    private var displayPowerEpochs: [String: UInt64] = [:]
    private var observedOnlineLocks: Set<String> = []
    private var powerEpoch: UInt64 = 0
    private var isSleeping: Bool { wakeState.isSuspended }
    private let logger: Logger

    init(defaults: UserDefaults = .standard, backend: DisplayBackend? = nil, startObserving: Bool = true,
         automaticScheduling: Bool? = nil) {
        self.defaults = defaults
        self.backend = backend ?? .live
        self.automaticScheduling = automaticScheduling ?? startObserving
        logger = startObserving
            ? Logger(subsystem: "ing.fuyaoskyrocket.FuyaoColorLock", category: "ModeLock")
            : Logger(OSLog.disabled)
        targets = Settings.modeLockTargets(defaults: defaults)
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
            let onlineLocks = Set(snapshot.map(\.id)).intersection(targets.keys)
            for identity in observedOnlineLocks.subtracting(onlineLocks) where targets[identity] != nil {
                displayWakeStates[identity, default: DisplayWakeState()].disconnected(
                    at: backend.now(), renewRetryBudget: applyingDisplayID != identity)
                displayPowerEpochs[identity, default: 0] &+= 1
            }
            // Failed catalog reads never change this set or renew retry budgets.
            observedOnlineLocks = onlineLocks
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
        refreshPowerState()
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
            refreshCatalog()
            guard !isApplying, !isSleeping, !DisplayMutationGate.isBusy else { return }
            guard let fresh = displays.first(where: { $0.id == display.id }), canCaptureTarget(for: fresh),
                  let mode = fresh.liveConnection?.currentMode else { return }
            saveTarget(ModeLockTarget(mode), for: fresh.id)
        } else {
            revisions[display.id, default: 0] += 1
            targets.removeValue(forKey: display.id)
            retries.removeValue(forKey: display.id)
            displayWakeStates.removeValue(forKey: display.id)
            observedOnlineLocks.remove(display.id)
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
        refreshCatalog()
        guard !isApplying, !isSleeping, !isSuspended(display.id), !DisplayMutationGate.isBusy else { return }
        let revision = revisions[display.id, default: 0]
        let wasLocked = targets[display.id] != nil
        let result = await performApply(mode, to: display).result
        if wasLocked, targets[display.id] != nil, revisions[display.id, default: 0] == revision {
            if result == .confirmed {
                saveTarget(ModeLockTarget(mode), for: display.id)
            } else {
                // An uncertain manual change must not be immediately pulled
                // back to the old lock target behind the user's action.
                retries[display.id, default: ModeLockRetry()].pause()
                logger.info("Mode lock paused; reason=manual-change-unconfirmed")
            }
        }
        updateLockStates()
        scheduleLockPass()
    }

    /// Called by the scheduler and by deterministic tests with a fake backend.
    func reconcileModeLocks() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer {
            isReconciling = false
            updateLockStates()
            scheduleLockPass()
        }
        refreshCatalog()
        guard !isSleeping else { return }
        for display in displays {
            guard !isSleeping else { break }
            guard let target = targets[display.id], !retry(for: display.id).isPaused,
                  !isSuspended(display.id),
                  retry(for: display.id).delay(at: backend.now()) == 0 else { continue }
            guard !isApplying, !DisplayMutationGate.isBusy else { break }
            guard backend.identity(display.cgDirectDisplayID) == display.id else { continue }
            guard case .restore(let mode) = ModeLockDecision.evaluate(target: target, connection: display.liveConnection) else {
                continue
            }
            guard retries[display.id, default: ModeLockRetry()].allowsAttempt(at: backend.now()) else {
                logger.info("Mode lock paused; reason=automatic-rate-limit")
                continue
            }
            let revision = revisions[display.id, default: 0]
            let epoch = powerEpoch
            let displayEpoch = displayPowerEpochs[display.id, default: 0]
            let outcome = await performApply(mode, to: display, automatic: true)
            let result = outcome.result
            guard targets[display.id] == target, revisions[display.id, default: 0] == revision else { continue }
            guard epoch == powerEpoch, displayEpoch == displayPowerEpochs[display.id, default: 0] else { continue }
            if result == .confirmed {
                retries[display.id, default: ModeLockRetry()].confirmed()
            } else if !outcome.submitted {
                retries[display.id, default: ModeLockRetry()].deferReadinessCheck(at: backend.now())
            } else if outcome.submitted, !isSleeping, !isSuspended(display.id),
                      backend.sessionAvailable() == true,
                      let current = displays.first(where: { $0.id == display.id }),
                      backend.displayIsAsleep(current.cgDirectDisplayID) == false,
                      backend.identity(current.cgDirectDisplayID) == display.id,
                      case .restore = ModeLockDecision.evaluate(target: target, connection: current.liveConnection) {
                retries[display.id, default: ModeLockRetry()].failed(at: backend.now())
                logger.info("Automatic recovery unconfirmed; consecutiveFailures=\(self.retry(for: display.id).failures, privacy: .public)")
            }
        }
    }

    func setSleeping(_ sleeping: Bool, source: String = "explicit") {
        let wasSuspended = isSleeping
        if sleeping {
            wakeState.sleepHint(at: backend.now())
            for identity in targets.keys { displayWakeStates[identity, default: DisplayWakeState()].sleepHint(at: backend.now()) }
            scheduledLockTask?.cancel()
            scheduledLockTask = nil
            scheduledLockAt = nil
            refreshTask?.cancel()
            refreshTask = nil
            logger.info("Sleep hint received; source=\(source, privacy: .public); automatic writes suspended")
        } else {
            wakeState.wakeHint(at: backend.now())
            for identity in targets.keys { displayWakeStates[identity, default: DisplayWakeState()].wakeHint(at: backend.now()) }
            logger.info("Wake hint received; source=\(source, privacy: .public); checking hardware and session readiness")
        }
        if !wasSuspended && isSleeping { powerEpoch &+= 1 }
        updateLockStates()
        scheduleWakeCheck()
    }

    func sessionBecameActive() {
        let wasSuspended = isSleeping
        wakeState.wakeHint(at: backend.now(), trustedPowerEvent: false)
        for identity in targets.keys {
            displayWakeStates[identity, default: DisplayWakeState()].wakeHint(at: backend.now(), trustedPowerEvent: false)
        }
        if !wasSuspended && isSleeping { powerEpoch &+= 1 }
        logger.info("Session activation hint received; rechecking observed availability")
        updateLockStates()
        scheduleWakeCheck()
    }

    private struct ApplyOutcome {
        let result: ModeApplyResult
        let submitted: Bool
    }

    private func performApply(_ mode: NativeConnectionMode, to display: PhysicalDisplay,
                              automatic: Bool = false) async -> ApplyOutcome {
        guard !isApplying, !isSleeping, !isSuspended(display.id),
              backend.sessionAvailable() == true, backend.displayIsAsleep(display.cgDirectDisplayID) == false,
              let live = display.liveConnection, live.isWritable, DisplayMutationGate.begin() else {
            applyResults[display.id] = .unavailable
            refreshCatalog()
            return ApplyOutcome(result: .unavailable, submitted: false)
        }
        isApplying = true
        applyingDisplayID = display.id
        applyResults[display.id] = .applying
        confirmedModes.removeValue(forKey: display.id)
        let epoch = powerEpoch
        let displayEpoch = displayPowerEpochs[display.id, default: 0]
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
            return completeApply(.unavailable, mode: mode, displayID: display.id, submitted: false)
        }
        switch backend.requestApply(mode, display.cgDirectDisplayID, live.currentMode, display.id) {
        case .unavailable:
            return completeApply(.unavailable, mode: mode, displayID: display.id, submitted: false)
        case .alreadyCurrent:
            return completeApply(.confirmed, mode: mode, displayID: display.id, submitted: false)
        case .requested:
            if automatic { retries[display.id, default: ModeLockRetry()].recordAttempt(at: backend.now()) }
            logger.info("Mode request submitted; automatic=\(automatic, privacy: .public)")
            break
        }

        var verifier = ModeReadbackVerifier(expected: mode)
        for _ in 0..<12 {
            do { try await backend.wait(500_000_000) }
            catch { return completeApply(.unconfirmed, mode: mode, displayID: display.id, submitted: true) }
            guard !isSleeping, !isSuspended(display.id), epoch == powerEpoch,
                  displayEpoch == displayPowerEpochs[display.id, default: 0], backend.sessionAvailable() == true,
                  backend.displayIsAsleep(display.cgDirectDisplayID) == false,
                  backend.identity(display.cgDirectDisplayID) == display.id else {
                return completeApply(.unconfirmed, mode: mode, displayID: display.id, submitted: true)
            }
            if verifier.observe(backend.connection(display.cgDirectDisplayID)?.currentMode) {
                return completeApply(.confirmed, mode: mode, displayID: display.id, submitted: true)
            }
        }
        return completeApply(.unconfirmed, mode: mode, displayID: display.id, submitted: true)
    }

    private func completeApply(_ result: ModeApplyResult, mode: NativeConnectionMode,
                               displayID: String, submitted: Bool) -> ApplyOutcome {
        if result == .confirmed { confirmedModes[displayID] = mode }
        applyResults[displayID] = result
        refreshCatalog()
        logger.notice("Mode readback completed; result=\(String(describing: self.applyResults[displayID] ?? result), privacy: .public)")
        return ApplyOutcome(result: applyResults[displayID] ?? result, submitted: submitted)
    }

    private func refreshPowerState() {
        let wasSuspended = isSleeping
        let sessionAvailable = backend.sessionAvailable()
        _ = wakeState.observe(
            displaySleepStates: displays.map { backend.displayIsAsleep($0.cgDirectDisplayID) },
            sessionAvailable: sessionAvailable, at: backend.now())
        if !wasSuspended && isSleeping { powerEpoch &+= 1 }
        if wasSuspended != isSleeping {
            logger.info("Hardware/session availability changed; suspended=\(self.isSleeping, privacy: .public)")
        }
        var recoveryCount = 0
        for identity in targets.keys {
            let display = displays.first { $0.id == identity }
            var state = displayWakeStates[identity] ?? DisplayWakeState()
            let previouslySuspended = state.isSuspended
            let recovered = state.observe(
                displaySleepStates: display.map { [backend.displayIsAsleep($0.cgDirectDisplayID)] } ?? [],
                sessionAvailable: sessionAvailable, at: backend.now())
            if !previouslySuspended && state.isSuspended { displayPowerEpochs[identity, default: 0] &+= 1 }
            displayWakeStates[identity] = state
            if recovered {
                retries[identity, default: ModeLockRetry()].resumeAfterWake()
                recoveryCount += 1
            }
        }
        if recoveryCount > 0 {
            logger.info("Display/session recovery confirmed; recoveredLocks=\(recoveryCount, privacy: .public); manual pauses retained")
        }
    }

    private func isSuspended(_ identity: String) -> Bool {
        displayWakeStates[identity]?.isSuspended == true
    }

    private func saveTarget(_ target: ModeLockTarget, for displayID: String) {
        revisions[displayID, default: 0] += 1
        targets[displayID] = target
        observedOnlineLocks.insert(displayID)
        retries[displayID] = ModeLockRetry()
        Settings.setModeLockTarget(target, for: displayID, defaults: defaults)
    }

    private func retry(for identity: String) -> ModeLockRetry { retries[identity] ?? ModeLockRetry() }

    private func canCaptureTarget(for display: PhysicalDisplay) -> Bool {
        guard !isApplying, !isSleeping, display.uuidString != nil,
              backend.sessionAvailable() == true, backend.displayIsAsleep(display.cgDirectDisplayID) == false,
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
                let lifecycle = displayWakeStates[identity] ?? wakeState
                if display == nil { state.phase = .waitingForDisplay }
                else if lifecycle.isSuspended { state.phase = lifecycle.isKnownAsleep ? .sleeping : .waking }
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
        if lockStates != states {
            let enabled = states.values.filter(\.isEnabled)
            let phases = enabled.map { String(describing: $0.phase) }.sorted().joined(separator: ",")
            let reasons = targets.keys.compactMap { retries[$0]?.pauseReason }
                .map { String(describing: $0) }.sorted().joined(separator: ",")
            logger.notice("Mode lock state changed; enabled=\(enabled.count, privacy: .public); phases=\(phases, privacy: .public); pauses=\(reasons, privacy: .public)")
            lockStates = states
        }
        scheduleLockMonitoring()
    }

    private func scheduleLockPass() {
        guard automaticScheduling else { return }
        scheduleWakeCheck()
        let delays = !isSleeping && !isReconciling && !isApplying ? displays.compactMap { display -> TimeInterval? in
            guard let target = targets[display.id], !retry(for: display.id).isPaused,
                  !isSuspended(display.id),
                  backend.identity(display.cgDirectDisplayID) == display.id,
                  case .restore = ModeLockDecision.evaluate(target: target, connection: display.liveConnection) else { return nil }
            return max(DisplayMutationGate.isBusy ? 1 : 0.25, retry(for: display.id).delay(at: backend.now()))
        } : []
        guard let delay = delays.min() else {
            scheduledLockTask?.cancel()
            scheduledLockTask = nil
            scheduledLockAt = nil
            return
        }
        let due = backend.now().addingTimeInterval(delay)
        if scheduledLockTask != nil, let scheduledLockAt, scheduledLockAt <= due { return }
        scheduledLockTask?.cancel()
        scheduledLockAt = due
        scheduledLockTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduledLockTask = nil
            self.scheduledLockAt = nil
            // The cancellable timer does not own an in-flight write/readback.
            // Turning a lock off cancels only work that has not been submitted.
            Task { [weak self] in await self?.reconcileModeLocks() }
        }
    }

    private func scheduleLockMonitoring() {
        guard automaticScheduling, !targets.isEmpty else {
            lockMonitorTask?.cancel()
            lockMonitorTask = nil
            return
        }
        guard lockMonitorTask == nil else { return }
        lockMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
                guard !Task.isCancelled, self != nil else { return }
                self?.checkLockedDisplays()
            }
        }
    }

    private func checkLockedDisplays() {
        // Only probe active lock connections here. The complete EDID/driver
        // catalog keeps its slower refresh cadence unless something changed.
        if let onlineIDs = backend.onlineDisplayIDs(), onlineIDs != Set(displays.map(\.cgDirectDisplayID)) {
            reload()
            return
        }
        refreshPowerState()
        for display in displays where targets[display.id] != nil {
            if backend.identity(display.cgDirectDisplayID) != display.id
                || backend.connection(display.cgDirectDisplayID) != display.liveConnection {
                reload()
                return
            }
        }
        updateLockStates()
        scheduleLockPass()
    }

    private func scheduleWakeCheck() {
        guard automaticScheduling, wakeCheckTask == nil,
              wakeState.shouldCheckAgain(at: backend.now())
                || displayWakeStates.values.contains(where: { $0.shouldCheckAgain(at: backend.now()) }) else { return }
        // Separate from reconfiguration debounce: repeated notifications must
        // not postpone every wake check until the driver's final event.
        wakeCheckTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.wakeCheckTask = nil
            self.reload()
        }
    }

    private func observeDisplayNotifications() {
        observe(NSApplication.didChangeScreenParametersNotification, on: .default, delay: 0.5)
        observe(nativeDisplayConfigurationChanged, on: .default, delay: 0.25)
        displayCallbackRegistered = CGDisplayRegisterReconfigurationCallback(displayConfigurationChanged, nil) == .success
        if !displayCallbackRegistered {
            logger.error("Display reconfiguration observer unavailable; periodic lock checks remain active")
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSleeping(true, source: name.rawValue) }
            }
            observers.append((center, token))
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSleeping(false, source: name.rawValue) }
            }
            observers.append((center, token))
        }
        let sessionToken = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionBecameActive() }
        }
        observers.append((center, sessionToken))
        let inactiveToken = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setSleeping(true, source: NSWorkspace.sessionDidResignActiveNotification.rawValue)
            }
        }
        observers.append((center, inactiveToken))
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, delay: TimeInterval) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(delay: delay) }
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
        guard automaticScheduling, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refreshTask = nil
            self?.reload()
        }
    }

    deinit {
        refreshTask?.cancel()
        scheduledLockTask?.cancel()
        wakeCheckTask?.cancel()
        lockMonitorTask?.cancel()
        pollTimer?.invalidate()
        if displayCallbackRegistered { CGDisplayRemoveReconfigurationCallback(displayConfigurationChanged, nil) }
        for (center, token) in observers { center.removeObserver(token) }
    }
}

private let nativeDisplayConfigurationChanged = Notification.Name("FuyaoColorLock.displayConfigurationChanged")

private func displayConfigurationChanged(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                         _ context: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    // Quartz callbacks only enqueue discovery. A mode change must never run
    // inside the system's reconfiguration callback.
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: nativeDisplayConfigurationChanged, object: nil)
    }
}
