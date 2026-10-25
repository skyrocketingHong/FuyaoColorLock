import CoreGraphics
import Foundation

@main
struct ModeLockTests {
    @MainActor
    static func main() async throws {
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
        print("Passed 14 fake-backend mode lock regression groups. No native setter was called.")
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
        monitor.setSleeping(false)
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
        fixture.hardware.onWait = { count in if count == 1 { monitor.setSleeping(true) } }
        await monitor.reconcileModeLocks()
        try expect(fixture.hardware.writes.count == 1 && monitor.lockState(for: display).phase == .sleeping,
                   "Sleep after submission must stop new writes and report waiting")
        try expect(monitor.applyResults[display.id] == .unconfirmed, "Sleeping before stable readback cannot confirm the write")
        fixture.hardware.onWait = nil
        monitor.setSleeping(false)
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
    }
    struct Write { let cgID: UInt32; let mode: NativeConnectionMode }
    var records = [Record()]
    var writes: [Write] = []
    var appliesRequests = true
    var unappliedDisplays: Set<UInt32> = []
    var now = Date(timeIntervalSince1970: 1_000)
    var waitCount = 0
    var onWait: ((Int) -> Void)?

    var backend: DisplayBackend {
        DisplayBackend(snapshot: { [self] in .success(records.filter(\.online).map(display)) },
            identity: { [self] id in records.first { $0.online && $0.cgID == id }?.identity },
            connection: { [self] id in records.first { $0.online && $0.cgID == id }.flatMap(connection) },
            requestApply: { [self] target, id, expected, identity in
                guard let index = records.firstIndex(where: { $0.online && $0.cgID == id && $0.identity == identity }),
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
            }, now: { [self] in now })
    }

    private func connection(_ record: Record) -> LiveDisplayConnection? {
        guard record.readable else { return nil }
        return LiveDisplayConnection(currentMode: record.current, modes: record.modes, isWritable: record.writable)
    }

    private func display(_ record: Record) -> PhysicalDisplay {
        PhysicalDisplay(id: record.identity, name: "Display A", cgDirectDisplayID: record.cgID,
            uuidString: String(record.identity.dropFirst(5)), timings: [], currentTimingID: nil,
            recordedLinkState: .unavailable, edid: nil, liveConnection: connection(record))
    }
}
