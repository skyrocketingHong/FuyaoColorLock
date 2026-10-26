import Foundation

/// A persistent format fingerprint. Native mode IDs are attachment-specific
/// and are deliberately excluded from the stored target.
struct ModeLockTarget: Codable, Hashable {
    let width: Int
    let height: Int
    let refreshRateHz: Double
    let bitDepth: Int
    let colorMode: String
    let colorGamut: String
    let hdrMode: String
    let isVRR: Bool

    init(_ mode: NativeConnectionMode) {
        width = mode.width
        height = mode.height
        refreshRateHz = mode.refreshRateHz
        bitDepth = mode.bitDepth
        colorMode = mode.colorMode
        colorGamut = mode.colorGamut
        hdrMode = mode.hdrMode
        isVRR = mode.isVRR
    }

    var isValid: Bool {
        width > 0 && height > 0 && refreshRateHz.isFinite && refreshRateHz > 0
            && bitDepth > 0 && bitDepth <= 64 && !colorMode.isEmpty && !colorGamut.isEmpty && !hdrMode.isEmpty
    }

    var title: String { descriptionMode.title }
    var timingLabel: String { descriptionMode.timingLabel }

    func matches(_ mode: NativeConnectionMode) -> Bool {
        !mode.isVirtual && self == ModeLockTarget(mode)
    }

    func preservesTiming(of mode: NativeConnectionMode) -> Bool {
        !mode.isVirtual && width == mode.width && height == mode.height
            && refreshRateHz == mode.refreshRateHz && hdrMode == mode.hdrMode && isVRR == mode.isVRR
    }

    private var descriptionMode: NativeConnectionMode {
        NativeConnectionMode(id: 0, width: width, height: height, refreshRateHz: refreshRateHz,
            bitDepth: bitDepth, colorMode: colorMode, colorGamut: colorGamut, hdrMode: hdrMode,
            isVRR: isVRR, isVirtual: false)
    }
}

enum ModeLockPhase: Equatable {
    case off, matching, restoring, waitingForDisplay, unavailable, incompatible, retryScheduled, paused, sleeping, waking
}

struct ModeLockState: Equatable {
    var isEnabled = false
    var canEnable = false
    var target: ModeLockTarget?
    var phase: ModeLockPhase = .off
}

enum ModeLockDecision: Equatable {
    case matching
    case restore(NativeConnectionMode)
    case unavailable
    case incompatible

    static func evaluate(target: ModeLockTarget, connection: LiveDisplayConnection?) -> Self {
        guard target.isValid, let connection else { return .unavailable }
        guard target.preservesTiming(of: connection.currentMode) else { return .incompatible }
        guard connection.isWritable else { return .unavailable }
        let matches = connection.modes.filter(target.matches)
        guard matches.count == 1, let match = matches.first else { return .unavailable }
        if target.matches(connection.currentMode) { return .matching }
        return .restore(match)
    }
}

/// Ordinary refreshes do not reset failure budgets. Confirmed recovery clears
/// consecutive failures; the independent rate budget still limits flapping.
struct ModeLockRetry {
    enum PauseReason { case manualChange, automaticFailure, rateLimit }
    private(set) var failures = 0
    private(set) var nextAttemptAt: Date?
    private(set) var pauseReason: PauseReason?
    var isPaused: Bool { pauseReason != nil }
    private var attempts: [Date] = []

    mutating func allowsAttempt(at now: Date) -> Bool {
        attempts.removeAll { now.timeIntervalSince($0) >= 60 }
        guard attempts.count < 3 else { pause(reason: .rateLimit); return false }
        return true
    }

    mutating func recordAttempt(at now: Date) { attempts.append(now) }
    mutating func deferReadinessCheck(at now: Date) {
        nextAttemptAt = max(nextAttemptAt ?? now, now.addingTimeInterval(1))
    }

    mutating func failed(at now: Date) {
        failures += 1
        if failures >= 3 {
            pauseReason = .automaticFailure
            nextAttemptAt = nil
        } else {
            nextAttemptAt = now.addingTimeInterval(failures == 1 ? 5 : 15)
        }
    }

    mutating func confirmed() { failures = 0; nextAttemptAt = nil }
    mutating func pause(reason: PauseReason = .manualChange) { pauseReason = reason; nextAttemptAt = nil }

    mutating func resumeAfterWake() {
        guard pauseReason != .manualChange else { return }
        self = ModeLockRetry()
    }

    func delay(at now: Date) -> TimeInterval {
        max(0, nextAttemptAt?.timeIntervalSince(now) ?? 0)
    }
}
