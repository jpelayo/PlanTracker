//
//  SessionTracker.swift
//  PlanTracker
//

import Foundation

@MainActor
final class SessionTracker {
    private var lastKnownUtilization: Double?
    private var lastKnownCreditsRemaining: Int?
    private var lastKnownOverageUsed: Int?
    private var noChangeCount = 0
    private var sessionStartTime: Date?
    private(set) var accumulatedSeconds: TimeInterval = 0
    private var lastResetDate: Date = .distantPast
    private var lastTickDate: Date = .distantPast

    init() {
        load()
    }

    /// Wall-clock total including current active session
    var totalSeconds: TimeInterval {
        guard let start = sessionStartTime else { return accumulatedSeconds }
        return accumulatedSeconds + Date().timeIntervalSince(start)
    }

    /// Called from UsageViewModel on every poll
    func processTick(fiveHourUtilization: Double?, prepaidCreditsRemaining: Int?, overageUsedCredits: Int?, minInterval: TimeInterval, resetHour: Int) {
        let now = Date()

        // Enforce minimum interval between ticks
        if lastTickDate != .distantPast {
            let elapsed = now.timeIntervalSince(lastTickDate)
            guard elapsed >= minInterval * 0.5 else { return }
        }
        lastTickDate = now

        checkDailyReset(now: now, resetHour: resetHour)

        let utilizationChanged = fiveHourUtilization != nil
            && lastKnownUtilization != nil
            && (fiveHourUtilization! * 10).rounded() != (lastKnownUtilization! * 10).rounded()
        let creditsChanged = prepaidCreditsRemaining != nil
            && lastKnownCreditsRemaining != nil
            && prepaidCreditsRemaining != lastKnownCreditsRemaining
        let overageChanged = overageUsedCredits != nil
            && lastKnownOverageUsed != nil
            && overageUsedCredits != lastKnownOverageUsed
        let activityDetected = utilizationChanged || creditsChanged || overageChanged

        // Need at least one prior observation before we can detect change
        let haveBaseline = lastKnownUtilization != nil || lastKnownCreditsRemaining != nil || lastKnownOverageUsed != nil

        if haveBaseline && activityDetected {
            // Something changed → start/continue session
            noChangeCount = 0
            if sessionStartTime == nil {
                sessionStartTime = now
                print("[SessionTracker] Session started")
            }
        } else if sessionStartTime != nil {
            // No change and session is active
            noChangeCount += 1
            print("[SessionTracker] No change count: \(noChangeCount)")
            if noChangeCount >= 2 {
                // End session
                if let start = sessionStartTime {
                    accumulatedSeconds += now.timeIntervalSince(start)
                    print("[SessionTracker] Session ended, accumulated: \(accumulatedSeconds)s")
                }
                sessionStartTime = nil
                noChangeCount = 0
            }
        }

        if let u = fiveHourUtilization { lastKnownUtilization = u }
        if let c = prepaidCreditsRemaining { lastKnownCreditsRemaining = c }
        if let o = overageUsedCredits { lastKnownOverageUsed = o }
        persist()
    }

    /// For demo mode
    func setMockAccumulated(_ seconds: TimeInterval) {
        accumulatedSeconds = seconds
        sessionStartTime = nil
        noChangeCount = 0
    }

    private func checkDailyReset(now: Date, resetHour: Int) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = resetHour
        components.minute = 0
        components.second = 0

        guard let todayReset = calendar.date(from: components) else { return }
        guard now >= todayReset && lastResetDate < todayReset else { return }

        print("[SessionTracker] Daily reset triggered at hour \(resetHour)")
        accumulatedSeconds = 0
        sessionStartTime = nil
        noChangeCount = 0
        lastKnownUtilization = nil
        lastKnownCreditsRemaining = nil
        lastKnownOverageUsed = nil
        lastResetDate = now
        persist()
    }

    func persist() {
        UserDefaults.standard.set(accumulatedSeconds, forKey: "sessionAccumulatedSeconds")
        UserDefaults.standard.set(lastResetDate.timeIntervalSince1970, forKey: "sessionLastResetDate")
        if let util = lastKnownUtilization {
            UserDefaults.standard.set(util, forKey: "sessionLastKnownUtilization")
        } else {
            UserDefaults.standard.removeObject(forKey: "sessionLastKnownUtilization")
        }
    }

    func load() {
        accumulatedSeconds = UserDefaults.standard.double(forKey: "sessionAccumulatedSeconds")

        let resetTimestamp = UserDefaults.standard.double(forKey: "sessionLastResetDate")
        if resetTimestamp > 0 {
            lastResetDate = Date(timeIntervalSince1970: resetTimestamp)
        }

        if UserDefaults.standard.object(forKey: "sessionLastKnownUtilization") != nil {
            lastKnownUtilization = UserDefaults.standard.double(forKey: "sessionLastKnownUtilization")
        }

        // Do NOT restore sessionStartTime — treat restart as implicit session end
        sessionStartTime = nil
        print("[SessionTracker] Loaded: accumulated=\(accumulatedSeconds)s, lastReset=\(lastResetDate)")
    }
}
