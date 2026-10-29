import Foundation

/// Notifications start a transition; observed hardware/session state completes
/// it. A missed wake notification must not latch the monitor asleep forever.
struct DisplayWakeState {
    private(set) var isSuspended = false
    private(set) var isKnownAsleep = false
    private(set) var recoveryDeadline: Date?
    private var settleUntil: Date?
    private var awakeSince: Date?
    private var hasRecoveryBoundary = false
    private var receivedWakeHint = false
    private var resumedInCurrentWindow = false
    private var lastAllAsleep = false

    mutating func disconnected(at now: Date, renewRetryBudget: Bool) {
        isSuspended = true
        isKnownAsleep = false
        hasRecoveryBoundary = hasRecoveryBoundary || renewRetryBudget
        awakeSince = nil
        settleUntil = nil
        receivedWakeHint = false
        resumedInCurrentWindow = false
        recoveryDeadline = now.addingTimeInterval(45)
    }

    mutating func sleepHint(at now: Date) {
        if !isSuspended {
            // willSleep can arrive before CGDisplayIsAsleep flips to true.
            settleUntil = now.addingTimeInterval(2)
            receivedWakeHint = false
            recoveryDeadline = now.addingTimeInterval(45)
            resumedInCurrentWindow = false
        }
        isSuspended = true
        isKnownAsleep = true
        hasRecoveryBoundary = true
        awakeSince = nil
    }

    mutating func wakeHint(at now: Date, trustedPowerEvent: Bool = true) {
        // didWake and screensDidWake can describe the same cycle. A late
        // duplicate inside the convergence window must not renew retry budgets.
        if resumedInCurrentWindow, shouldCheckAgain(at: now) { return }
        if !receivedWakeHint {
            settleUntil = max(settleUntil ?? now, now.addingTimeInterval(4))
            awakeSince = nil
            receivedWakeHint = true
        }
        if trustedPowerEvent { hasRecoveryBoundary = true }
        isSuspended = true
        if recoveryDeadline == nil || recoveryDeadline! < now {
            recoveryDeadline = now.addingTimeInterval(45)
        }
    }

    /// Returns true once for an observed recovery after sleep/session loss.
    mutating func observe(displaySleepStates: [Bool?], sessionAvailable: Bool?, at now: Date) -> Bool {
        let known = displaySleepStates.compactMap { $0 }
        let allAsleep = !displaySleepStates.isEmpty && known.count == displaySleepStates.count
            && known.allSatisfy { $0 }
        let anyAwake = known.contains(false)
        isKnownAsleep = allAsleep
        let enteredActualSleep = allAsleep && !lastAllAsleep
        lastAllAsleep = allAsleep

        if allAsleep || sessionAvailable != true {
            if !isSuspended || enteredActualSleep {
                settleUntil = nil
                receivedWakeHint = false
                recoveryDeadline = now.addingTimeInterval(45)
                resumedInCurrentWindow = false
            }
            isSuspended = true
            // A failed session read is not evidence of a new recovery cycle.
            if allAsleep || sessionAvailable == false { hasRecoveryBoundary = true }
            awakeSince = nil
            return false
        }

        guard isSuspended else { return false }
        guard anyAwake, sessionAvailable == true, now >= (settleUntil ?? .distantPast) else {
            awakeSince = nil
            return false
        }
        guard let first = awakeSince else {
            awakeSince = now
            if !shouldCheckAgain(at: now) {
                recoveryDeadline = now.addingTimeInterval(30)
            }
            return false
        }
        guard now.timeIntervalSince(first) >= 1 else { return false }

        let recovered = hasRecoveryBoundary
        isSuspended = false
        hasRecoveryBoundary = false
        awakeSince = nil
        settleUntil = nil
        receivedWakeHint = false
        resumedInCurrentWindow = true
        // Driver modes may become available after the screen is visibly awake.
        recoveryDeadline = now.addingTimeInterval(30)
        return recovered
    }

    func shouldCheckAgain(at now: Date) -> Bool {
        recoveryDeadline.map { now < $0 } ?? false
    }
}
