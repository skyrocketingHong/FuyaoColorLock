import CoreGraphics
import Foundation

@main
struct ModeLockTests {
    @MainActor
    static func main() async throws {
        try await missingWakeNotificationDoesNotLatchSleeping()
        try await wakeHintsRequireStableHardwareReadiness()
        try await lockedSessionWaitsWithoutSpendingRetries()
        try await automaticPausesResumeButManualPausesSurviveWake()
        try await unknownSessionReadDoesNotResetAutomaticPause()
        try await awakeDisplaysDoNotReleaseSleepingTargets()
        try await lateModesAreRetriedAfterHardwareWake()
        try wakeWindowsAreBoundedAndRenewAfterLongSleep()
        try await duplicateWakeHintsDoNotRenewFailureBudgets()
        try await unsubmittedRequestsBackOffWithoutFailureBudget()
        try await defaultsAndPersistence()
        try await restoresDriftAndVerifies()
        try await reconnectsWithFreshIdentifiers()
        try await refusesChangedTimingAndAmbiguousTargets()
        try await disablingDoesNotRescheduleSubmittedWrites()
        try await manualChangesUpdateOrPauseTheLock()
        try await failuresHaveBackoffAndPause()
        try await repeatedSuccessfulChangesAreBounded()
        try await waitsForGateAndSleepWithoutStarvingDisplays()
        try await oneDisplayFailureDoesNotStarveAnother()
        try await disconnectionDoesNotConsumeFailureRetries()
        try await inFlightSleepWaitsForWake()
        try await readbackRejectsReusedDisplayIdentifiers()
        try await invalidPersistenceIsIgnored()
        print("Passed 24 fake-backend mode lock regression groups. No native setter was called.")
    }

    @MainActor
    private static func missingWakeNotificationDoesNotLatchSleeping() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].asleep = true
        monitor.setSleeping(true)
        monitor.reload()
        fixture.hardware.records[0].asleep = false
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.now.addTimeInterval(30)
        monitor.reload()
        fixture.hardware.now.addTimeInterval(2)
        monitor.reload()
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1,
                   "A missing wake notification must not permanently suppress an awake display's lock")
    }

    @MainActor
    private static func wakeHintsRequireStableHardwareReadiness() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].asleep = true
        monitor.setSleeping(true)
        monitor.reload()
        monitor.setSleeping(false)
        fixture.hardware.now.addTimeInterval(8)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.isEmpty, "A wake hint cannot authorize a still-asleep target")
        fixture.hardware.records[0].asleep = false
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        for _ in 0..<5 { monitor.reload(); await monitor.reconcileModeLocks() }
        try expect(fixture.hardware.writes.isEmpty, "Repeated synchronous reloads cannot replace elapsed awake observation time")
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "A stable awake target can recover")

        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        monitor.setSleeping(true)
        monitor.setSleeping(false)
        fixture.hardware.now.addTimeInterval(3.9)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "Ordinary polling cannot bypass the four-second wake settling gate")
        fixture.hardware.now.addTimeInterval(0.1)
        monitor.reload()
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 2, "The next genuine cycle can recover after settling")
    }

    @MainActor
    private static func lockedSessionWaitsWithoutSpendingRetries() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.sessionAvailable = false
        monitor.setSleeping(false)
        for _ in 0..<5 {
            fixture.hardware.now.addTimeInterval(5)
            await monitor.reconcileModeLocks()
        }
        try expect(fixture.hardware.writes.isEmpty, "A lit but unavailable user session must not consume write retries")
        fixture.hardware.sessionAvailable = true
        monitor.reload()
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1 && monitor.lockState(for: display).phase == .matching,
                   "Session readiness must resume without requiring a manual lock toggle")
    }

    @MainActor
    private static func automaticPausesResumeButManualPausesSurviveWake() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.appliesRequests = false
        for delay in [0.0, 5, 15] {
            fixture.hardware.now.addTimeInterval(delay)
            await monitor.reconcileModeLocks()
        }
        try expect(monitor.lockState(for: display).phase == .paused, "Fixture must reach automatic failure pause")
        fixture.hardware.records[0].asleep = true
        monitor.setSleeping(true)
        monitor.reload()
        fixture.hardware.appliesRequests = true
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 4, "A confirmed new wake cycle should rearm an automatic failure pause")

        fixture.hardware.appliesRequests = false
        await monitor.apply(mode(id: 2, format: "RGBLimitedRange"), to: try fixture.display(in: monitor))
        let count = fixture.hardware.writes.count
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.records[0].asleep = true
        monitor.setSleeping(true)
        monitor.reload()
        fixture.hardware.appliesRequests = true
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == count && monitor.lockState(for: display).phase == .paused,
                   "A failed manual change remains paused across wake instead of restoring the old target")
    }

    @MainActor
    private static func unknownSessionReadDoesNotResetAutomaticPause() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.appliesRequests = false
        for delay in [0.0, 5, 15] { fixture.hardware.now.addTimeInterval(delay); await monitor.reconcileModeLocks() }
        fixture.hardware.sessionAvailable = nil
        monitor.reload()
        fixture.hardware.sessionAvailable = true
        fixture.hardware.now.addTimeInterval(2)
        monitor.reload()
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 3 && monitor.lockState(for: display).phase == .paused,
                   "A failed session read is not a genuine wake cycle and cannot renew retry budgets")
    }

    @MainActor
    private static func awakeDisplaysDoNotReleaseSleepingTargets() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.hardware.records.append(FakeHardware.Record(identity: "uuid-test-b", cgID: 102))
        let monitor = fixture.monitor()
        for display in monitor.displays { monitor.setModeLock(true, for: display) }
        fixture.hardware.records[0].asleep = true
        for index in fixture.hardware.records.indices {
            fixture.hardware.records[index].current = mode(id: 2, format: "RGBLimitedRange")
        }
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.map(\.cgID) == [102], "An awake lock recovers independently of a sleeping lock")
        fixture.hardware.records[0].asleep = false
        for _ in 0..<3 { monitor.reload(); await monitor.reconcileModeLocks() }
        try expect(fixture.hardware.writes.count == 1, "Another awake display must not waive this target's stability observation")
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.map(\.cgID) == [102, 101], "The second target recovers after its own stable wake")
    }

    @MainActor
    private static func lateModesAreRetriedAfterHardwareWake() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        monitor.setModeLock(true, for: try fixture.display(in: monitor))
        fixture.hardware.records[0].asleep = true
        monitor.setSleeping(true)
        monitor.reload()
        fixture.hardware.records[0].readable = false
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.isEmpty, "Hardware wake does not imply that native mode data is ready")
        fixture.hardware.now.addTimeInterval(8)
        fixture.hardware.records[0].readable = true
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "Late native modes remain eligible inside the wake convergence period")
    }

    private static func wakeWindowsAreBoundedAndRenewAfterLongSleep() throws {
        var state = DisplayWakeState()
        let start = Date(timeIntervalSince1970: 1000)
        state.sleepHint(at: start)
        _ = state.observe(displaySleepStates: [true], sessionAvailable: true, at: start)
        let later = start.addingTimeInterval(3600)
        try expect(!state.shouldCheckAgain(at: later), "Read-only burst checks must stop during a long sleep")
        try expect(!state.observe(displaySleepStates: [false], sessionAvailable: true, at: later),
                   "One awake sample does not settle a wake")
        try expect(state.shouldCheckAgain(at: later), "First awake observation after expiry must schedule the follow-up")
        try expect(state.observe(displaySleepStates: [false], sessionAvailable: true, at: later.addingTimeInterval(1)),
                   "A second timed observation completes recovery")
        try expect(!state.shouldCheckAgain(at: later.addingTimeInterval(32)), "The resumed convergence window is bounded")

        state.sleepHint(at: later.addingTimeInterval(40))
        state.wakeHint(at: later.addingTimeInterval(41))
        _ = state.observe(displaySleepStates: [true], sessionAvailable: true, at: later.addingTimeInterval(42))
        state.wakeHint(at: later.addingTimeInterval(43))
        _ = state.observe(displaySleepStates: [false], sessionAvailable: true, at: later.addingTimeInterval(46))
        try expect(state.isSuspended, "A new actual sleep during recovery starts a new wake settling interval")
        _ = state.observe(displaySleepStates: [false], sessionAvailable: true, at: later.addingTimeInterval(47))
        try expect(state.observe(displaySleepStates: [false], sessionAvailable: true, at: later.addingTimeInterval(48)),
                   "The second actual wake settles independently")
    }

    @MainActor
    private static func duplicateWakeHintsDoNotRenewFailureBudgets() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.appliesRequests = false
        for delay in [0.0, 5, 15] { fixture.hardware.now.addTimeInterval(delay); await monitor.reconcileModeLocks() }
        fixture.hardware.appliesRequests = true
        // The real power-wake event still creates a recovery boundary if its
        // corresponding sleep notification was missed.
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        for _ in 0..<3 {
            fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
            await monitor.reconcileModeLocks()
        }
        let count = fixture.hardware.writes.count
        try expect(monitor.lockState(for: display).phase == .paused, "Fixture must exhaust the new cycle's rate budget")
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == count && monitor.lockState(for: display).phase == .paused,
                   "Duplicate wake hints in one convergence window must not provide unlimited retries")
    }

    @MainActor
    private static func unsubmittedRequestsBackOffWithoutFailureBudget() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.rejectsRequests = true
        for _ in 0..<5 { await monitor.reconcileModeLocks() }
        try expect(fixture.hardware.requestCount == 1 && fixture.hardware.writes.isEmpty,
                   "An unsubmitted readiness failure must have a short recheck delay")
        for _ in 0..<5 { fixture.hardware.now.addTimeInterval(1); await monitor.reconcileModeLocks() }
        try expect(monitor.lockState(for: display).phase != .paused,
                   "Unsubmitted requests cannot exhaust the real-write failure budget")
        fixture.hardware.rejectsRequests = false
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "Readiness can recover without a manual retry")
    }

    @MainActor
    private static func defaultsAndPersistence() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.defaults.set(true, forKey: "lock.Display A-101.enabled")
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        try expect(!monitor.lockState(for: display).isEnabled, "A legacy fake-lock flag must never enable native writes")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.isEmpty, "Default startup must be read-only")
        monitor.setModeLock(true, for: display)
        try expect(monitor.lockState(for: display).phase == .matching, "An enabled lock reflects the current matching format")
        let data = fixture.defaults.data(forKey: "nativeModeLock.v1.uuid-test-a")!
        try expect(!String(decoding: data, as: UTF8.self).contains("\"id\""), "Volatile native IDs must not be persisted")
        fixture.hardware.records[0].current = mode(id: 900)
        fixture.hardware.records[0].modes = [mode(id: 900), mode(id: 901, format: "RGBLimitedRange")]
        let reopened = fixture.monitor()
        try expect(reopened.lockState(for: try fixture.display(in: reopened)).phase == .matching,
                   "A stored semantic target must survive changed native IDs")
        reopened.setModeLock(false, for: try fixture.display(in: reopened))
        try expect(Settings.modeLockTarget(for: display.id, defaults: fixture.defaults) == nil, "Disabling must persist")
    }

    @MainActor
    private static func restoresDriftAndVerifies() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        monitor.reload()
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "One drift should produce one native write request")
        try expect(fixture.hardware.waitCount == 2, "Automatic restoration requires two matching reads")
        try expect(monitor.applyResults[display.id] == .confirmed, "A matching readback should confirm system state")
        try expect(monitor.lockState(for: display).phase == .matching, "The lock should return to matching")
        monitor.reload()
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "Self-generated reconfiguration must not repeat an already matching write")
    }

    @MainActor
    private static func reconnectsWithFreshIdentifiers() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].online = false
        monitor.reload()
        try expect(monitor.lockState(for: display).phase == .waitingForDisplay, "Disconnected locks wait without guessing")
        fixture.hardware.records[0].online = true
        fixture.hardware.records[0].cgID = 202
        fixture.hardware.records[0].current = mode(id: 502, format: "RGBLimitedRange")
        fixture.hardware.records[0].modes = [mode(id: 501), mode(id: 502, format: "RGBLimitedRange")]
        await monitor.reconcileModeLocks()
        let write = try require(fixture.hardware.writes.first, "Reconnect should restore the available semantic target")
        try expect(write.cgID == 202 && write.mode.id == 501, "Restoration must use freshly enumerated display and native IDs")
    }

    @MainActor
    private static func refusesChangedTimingAndAmbiguousTargets() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(width: 2560)
        await monitor.reconcileModeLocks()
        try expect(monitor.lockState(for: display).phase == .incompatible && fixture.hardware.writes.isEmpty,
                   "A lock must not undo a user resolution change")
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.records[0].modes = [mode(id: 1), mode(id: 7), mode(id: 2, format: "RGBLimitedRange")]
        await monitor.reconcileModeLocks()
        try expect(monitor.lockState(for: display).phase == .unavailable && fixture.hardware.writes.isEmpty,
                   "Duplicate semantic matches must remain unavailable")
        fixture.hardware.records[0].readable = false
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.isEmpty, "Missing live mode is not permission to guess a timing")
        fixture.hardware.records[0].readable = true
        fixture.hardware.records[0].current = mode()
        fixture.hardware.records[0].modes = [mode()]
        fixture.hardware.records[0].writable = false
        await monitor.reconcileModeLocks()
        try expect(monitor.lockState(for: display).phase == .unavailable,
                   "A matching value must not hide a lost restoration capability")
    }

    @MainActor
    private static func disablingDoesNotRescheduleSubmittedWrites() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.onWait = { count in
            if count == 1 { monitor.setModeLock(false, for: display) }
        }
        await monitor.reconcileModeLocks()
        try expect(!monitor.lockState(for: display).isEnabled, "A disable during readback must stay disabled")
        try expect(monitor.applyResults[display.id] == .confirmed && fixture.hardware.waitCount == 2,
                   "A submitted write still needs accurate readback after the lock is disabled")
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        monitor.reload()
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "Disabling must prevent a second restoration")
    }

    @MainActor
    private static func manualChangesUpdateOrPauseTheLock() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        let tenBit = mode(id: 3, depth: 10)
        fixture.hardware.records[0].modes.append(tenBit)
        monitor.setModeLock(true, for: display)
        await monitor.apply(tenBit, to: try fixture.display(in: monitor))
        try expect(monitor.lockState(for: display).target == ModeLockTarget(tenBit), "A confirmed manual apply becomes the lock target")
        fixture.hardware.records[0].current = mode()
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.last?.mode == tenBit, "An active lock must not pull back to the former target")
        fixture.hardware.appliesRequests = false
        await monitor.apply(mode(), to: try fixture.display(in: monitor))
        let count = fixture.hardware.writes.count
        try expect(monitor.lockState(for: display).phase == .paused, "An unconfirmed manual action pauses automatic restoration")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == count, "An uncertain manual action must not be followed by an automatic counter-write")
    }

    @MainActor
    private static func failuresHaveBackoffAndPause() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.appliesRequests = false
        await monitor.reconcileModeLocks()
        for _ in 0..<4 { monitor.reload(); await monitor.reconcileModeLocks() }
        try expect(fixture.hardware.writes.count == 1, "Refresh events must not reset the first backoff")
        fixture.hardware.now.addTimeInterval(5)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 2, "The first retry becomes eligible after five seconds")
        fixture.hardware.now.addTimeInterval(14)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 2, "The second backoff lasts fifteen seconds")
        fixture.hardware.now.addTimeInterval(1)
        await monitor.reconcileModeLocks()
        try expect(monitor.lockState(for: display).phase == .paused, "Three failed readbacks pause restoration")
        fixture.hardware.now.addTimeInterval(600)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 3, "Time and polls do not silently clear a pause")
        fixture.hardware.appliesRequests = true
        monitor.retryModeLock(for: display)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 4 && monitor.lockState(for: display).phase == .matching,
                   "Explicit retry clears the budget and verifies the next result")
    }

    @MainActor
    private static func repeatedSuccessfulChangesAreBounded() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        for _ in 0..<4 {
            fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
            await monitor.reconcileModeLocks()
        }
        try expect(fixture.hardware.writes.count == 3 && monitor.lockState(for: display).phase == .paused,
                   "Repeated drift cannot cause unlimited successful reconfiguration loops")
        var retry = ModeLockRetry()
        retry.failed(at: Date())
        retry.confirmed()
        try expect(retry.failures == 0, "A verified restoration ends a consecutive failure sequence")
    }

    @MainActor
    private static func waitsForGateAndSleepWithoutStarvingDisplays() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.hardware.records.append(FakeHardware.Record(identity: "uuid-test-b", cgID: 102))
        let monitor = fixture.monitor()
        for display in monitor.displays { monitor.setModeLock(true, for: display) }
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.records[1].current = mode(id: 2, format: "RGBLimitedRange")
        try expect(DisplayMutationGate.begin(), "Test must start without a held gate")
        await monitor.reconcileModeLocks()
        DisplayMutationGate.end()
        try expect(fixture.hardware.writes.isEmpty, "EDID or another writer owns the shared gate")
        monitor.setSleeping(true)
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.isEmpty, "Sleep must suppress new writes")
        fixture.finishWake(monitor)
        await monitor.reconcileModeLocks()
        try expect(Set(fixture.hardware.writes.map(\.cgID)) == [101, 102], "Both locked displays should get a serialized recovery")
    }

    @MainActor
    private static func disconnectionDoesNotConsumeFailureRetries() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.onWait = { count in if count == 1 { fixture.hardware.records[0].online = false } }
        await monitor.reconcileModeLocks()
        try expect(monitor.lockState(for: display).phase == .waitingForDisplay, "Readback loss waits for the same stable identity")
        fixture.hardware.onWait = nil
        fixture.hardware.records[0].online = true
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 2, "Reconnect after missing readback does not inherit a failure backoff")
    }

    @MainActor
    private static func oneDisplayFailureDoesNotStarveAnother() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.hardware.records.append(FakeHardware.Record(identity: "uuid-test-b", cgID: 102))
        let monitor = fixture.monitor()
        for display in monitor.displays { monitor.setModeLock(true, for: display) }
        for index in fixture.hardware.records.indices {
            fixture.hardware.records[index].current = mode(id: 2, format: "RGBLimitedRange")
        }
        fixture.hardware.unappliedDisplays = [101]
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.map(\.cgID) == [101, 102], "A failed first display must not starve the second")
        try expect(monitor.lockStates["uuid-test-a"]?.phase == .retryScheduled,
                   "The failed display should retain its own backoff")
        try expect(monitor.lockStates["uuid-test-b"]?.phase == .matching,
                   "The second display should finish its verified recovery")
    }

    @MainActor
    private static func inFlightSleepWaitsForWake() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.onWait = { count in
            if count == 1 {
                fixture.hardware.records[0].asleep = true
                monitor.setSleeping(true)
            }
        }
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1 && monitor.lockState(for: display).phase == .sleeping,
                   "Sleep after submission must stop new writes and report waiting")
        try expect(monitor.applyResults[display.id] == .unconfirmed, "Sleeping before stable readback cannot confirm the write")
        fixture.hardware.onWait = nil
        fixture.finishWake(monitor)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 2 && monitor.lockState(for: display).phase == .matching,
                   "Wake recovery should not inherit a sleep-induced failure backoff")
    }

    @MainActor
    private static func readbackRejectsReusedDisplayIdentifiers() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let monitor = fixture.monitor()
        let display = try fixture.display(in: monitor)
        monitor.setModeLock(true, for: display)
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        fixture.hardware.onWait = { count in
            if count == 1 { fixture.hardware.records[0].identity = "uuid-different-display" }
        }
        await monitor.reconcileModeLocks()
        try expect(monitor.applyResults[display.id] == .unconfirmed
                   && monitor.lockState(for: display).phase == .waitingForDisplay,
                   "A reused CG ID cannot confirm the former physical display")
        fixture.hardware.onWait = nil
        fixture.hardware.records[0].current = mode(id: 2, format: "RGBLimitedRange")
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1, "The old lock must never be applied to the replacement identity")
    }

    @MainActor
    private static func invalidPersistenceIsIgnored() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.defaults.set(Data("not-json".utf8), forKey: "nativeModeLock.v1.uuid-test-a")
        let monitor = fixture.monitor()
        try expect(!monitor.lockState(for: try fixture.display(in: monitor)).isEnabled, "Corrupt preferences must not enable an automatic write")
        Settings.setModeLockTarget(ModeLockTarget(mode()), for: "unstable-101", defaults: fixture.defaults)
        try expect(Settings.modeLockTarget(for: "unstable-101", defaults: fixture.defaults) == nil,
                   "Transient display identities must not become persistent lock keys")
    }

    static func mode(id: UInt64 = 1, width: Int = 3840, depth: Int = 8, format: String = "RGBFullRange") -> NativeConnectionMode {
        NativeConnectionMode(id: id, width: width, height: 2160, refreshRateHz: 60,
            bitDepth: depth, colorMode: format, colorGamut: "gamut_SRGB", hdrMode: "SDR", isVRR: false, isVirtual: false)
    }

    private struct Failure: Error { let message: String }
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(message: message) }
        return value
    }

    @MainActor
    private final class Fixture {
        let suite = "FuyaoColorLockTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let hardware = FakeHardware()
        init() { defaults = UserDefaults(suiteName: suite)! }
        func clean() { defaults.removePersistentDomain(forName: suite) }
        func monitor() -> DisplayGuard {
            DisplayGuard(defaults: defaults, backend: hardware.backend, startObserving: false)
        }
        func display(in monitor: DisplayGuard) throws -> PhysicalDisplay {
            try require(monitor.displays.first, "Expected a fake display")
        }
        func finishWake(_ monitor: DisplayGuard) {
            for index in hardware.records.indices { hardware.records[index].asleep = false }
            monitor.setSleeping(false)
            hardware.now.addTimeInterval(4)
            monitor.reload()
            hardware.now.addTimeInterval(1)
            monitor.reload()
        }
    }
}

@MainActor
private final class FakeHardware {
    struct Record {
        var identity = "uuid-test-a"
        var cgID: UInt32 = 101
        var current = ModeLockTests.mode()
        var modes = [ModeLockTests.mode(), ModeLockTests.mode(id: 2, format: "RGBLimitedRange")]
        var online = true
        var readable = true
        var writable = true
        var asleep = false
    }
    struct Write { let cgID: UInt32; let mode: NativeConnectionMode }
    var records = [Record()]
    var writes: [Write] = []
    var appliesRequests = true
    var unappliedDisplays: Set<UInt32> = []
    var now = Date(timeIntervalSince1970: 1_000)
    var waitCount = 0
    var onWait: ((Int) -> Void)?
    var sessionAvailable: Bool? = true
    var rejectsRequests = false
    var requestCount = 0

    var backend: DisplayBackend {
        DisplayBackend(snapshot: { [self] in .success(records.filter(\.online).map(display)) },
            identity: { [self] id in records.first { $0.online && $0.cgID == id }?.identity },
            connection: { [self] id in records.first { $0.online && $0.cgID == id }.flatMap(connection) },
            requestApply: { [self] target, id, expected, identity in
                requestCount += 1
                if rejectsRequests { return .unavailable }
                guard let index = records.firstIndex(where: { $0.online && $0.cgID == id && $0.identity == identity }),
                      !records[index].asleep, sessionAvailable == true,
                      records[index].current == expected, records[index].modes.filter({ $0 == target }).count == 1 else {
                    return .unavailable
                }
                if target == records[index].current { return .alreadyCurrent }
                writes.append(Write(cgID: id, mode: target))
                if appliesRequests && !unappliedDisplays.contains(id) { records[index].current = target }
                return .requested
            },
            wait: { [self] nanoseconds in
                now.addTimeInterval(Double(nanoseconds) / 1_000_000_000)
                waitCount += 1
                onWait?(waitCount)
            }, now: { [self] in now },
            displayIsAsleep: { [self] id in records.first { $0.online && $0.cgID == id }?.asleep },
            sessionAvailable: { [self] in sessionAvailable })
    }

    private func connection(_ record: Record) -> LiveDisplayConnection? {
        guard record.readable else { return nil }
        return LiveDisplayConnection(currentMode: record.current, modes: record.modes,
                                     isWritable: record.writable && !record.asleep)
    }

    private func display(_ record: Record) -> PhysicalDisplay {
        PhysicalDisplay(id: record.identity, name: "Display A", cgDirectDisplayID: record.cgID,
            uuidString: String(record.identity.dropFirst(5)), timings: [], currentTimingID: nil,
            recordedLinkState: .unavailable, edid: nil, liveConnection: connection(record))
    }
}
