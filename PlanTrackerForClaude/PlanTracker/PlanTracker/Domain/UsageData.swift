//
//  UsageData.swift
//  PlanTracker
//

import Foundation

struct UsageData: Codable, Sendable, Equatable {
    nonisolated static let cosmeticPrepaidResidueThresholdMinorUnits = 1

    let fiveHourUtilization: Double?
    let fiveHourResetsAt: Date?
    let sevenDayUtilization: Double?
    let sevenDayResetsAt: Date?
    let sevenDayOpusUtilization: Double?
    let sevenDayOpusResetsAt: Date?
    let sevenDaySonnetUtilization: Double?
    let sevenDaySonnetResetsAt: Date?
    let sevenDayScopedLabel: String?
    let sevenDayScopedUtilization: Double?
    let sevenDayScopedResetsAt: Date?
    let extraUsageUtilization: Double?
    let extraUsageResetsAt: Date?
    let planTier: PlanTier
    let planDisplayNameOverride: String?
    let prepaidCreditsRemaining: Int?  // Minor units (cents)
    let prepaidCreditsTotal: Int?      // Minor units (cents)
    let prepaidCreditsCurrency: String?
    let prepaidAutoReloadEnabled: Bool?
    let overageMonthlyLimit: Int?      // Minor units (cents)
    let overageUsedCredits: Int?       // Minor units (cents)
    let overageCurrency: String?
    let overageEnabled: Bool?
    let overageOutOfCredits: Bool?

    var hasMonetaryExtraCredits: Bool {
        hasAvailablePrepaidCredits || hasStartedExtraUsageSpend
    }

    var hasExtraUsageAccounting: Bool {
        hasAvailablePrepaidCredits
            || overageEnabled == true
            || overageMonthlyLimit != nil
            || overageUsedCredits != nil
    }

    var hasAvailablePrepaidCredits: Bool {
        guard let currency = prepaidCreditsCurrency else { return false }
        return effectivePrepaidCreditsRemaining > 0 && !currency.isEmpty
    }

    var hasStartedExtraUsageSpend: Bool {
        guard let used = overageUsedCredits,
              let limit = overageMonthlyLimit,
              let currency = overageCurrency else { return false }
        return used > 0 && limit > 0 && !currency.isEmpty
    }

    var planDisplayName: String {
        guard let override = planDisplayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
              !override.isEmpty else {
            return planTier.displayName
        }
        return override
    }

    /// Returns remaining percentage (100 - utilization)
    var fiveHourRemaining: Double? {
        guard let util = fiveHourUtilization else { return nil }
        return 100 - util
    }

    var sevenDayRemaining: Double? {
        guard let util = sevenDayUtilization else { return nil }
        return 100 - util
    }

    var sevenDayOpusRemaining: Double? {
        guard let util = sevenDayOpusUtilization else { return nil }
        return 100 - util
    }

    var sevenDaySonnetRemaining: Double? {
        guard let util = sevenDaySonnetUtilization else { return nil }
        return 100 - util
    }

    var sevenDayScopedRemaining: Double? {
        guard let util = sevenDayScopedUtilization else { return nil }
        return 100 - util
    }

    var extraUsageRemaining: Double? {
        guard let util = extraUsageUtilization else { return nil }
        return 100 - util
    }

    var prepaidCreditsUtilization: Double? {
        guard hasAvailablePrepaidCredits else { return nil }
        guard let total = effectivePrepaidCreditsTotal,
              total > 0 else { return nil }
        let remaining = effectivePrepaidCreditsRemaining
        let used = Double(max(0, min(total, total - remaining)))
        return (used / Double(total)) * 100
    }

    var prepaidCreditsRemainingRatio: Double? {
        guard hasAvailablePrepaidCredits else { return nil }
        guard let total = effectivePrepaidCreditsTotal,
              total > 0 else { return nil }
        let remaining = effectivePrepaidCreditsRemaining
        return Double(max(0, min(remaining, total))) / Double(total)
    }

    var prepaidCreditsRemainingFormatted: String? {
        guard hasAvailablePrepaidCredits else { return nil }
        guard let currency = prepaidCreditsCurrency else { return nil }
        return formatCurrency(amount: effectivePrepaidCreditsRemaining, currency: currency)
    }

    var prepaidCreditsTotalFormatted: String? {
        guard hasAvailablePrepaidCredits else { return nil }
        guard let total = effectivePrepaidCreditsTotal,
              let currency = prepaidCreditsCurrency else { return nil }
        return formatCurrency(amount: total, currency: currency)
    }

    var prepaidCreditsSpent: Int? {
        guard hasAvailablePrepaidCredits else { return nil }
        guard let total = effectivePrepaidCreditsTotal else { return nil }
        let remaining = effectivePrepaidCreditsRemaining
        return max(0, min(total, total - remaining))
    }

    var prepaidCreditsSpentFormatted: String? {
        guard let spent = prepaidCreditsSpent,
              let currency = prepaidCreditsCurrency else { return nil }
        return formatCurrency(amount: spent, currency: currency)
    }

    private func formatCurrency(amount: Int, currency: String) -> String {
        let dollars = Double(amount) / 100.0
        return String(format: "%.2f %@", dollars, currency)
    }

    var formattedFiveHourReset: String? {
        guard let date = fiveHourResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var formattedSevenDayReset: String? {
        guard let date = sevenDayResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var formattedSevenDayOpusReset: String? {
        guard let date = sevenDayOpusResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var formattedSevenDaySonnetReset: String? {
        guard let date = sevenDaySonnetResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var formattedSevenDayScopedReset: String? {
        guard let date = sevenDayScopedResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var formattedExtraUsageReset: String? {
        guard let date = extraUsageResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var overageUtilization: Double? {
        guard let used = overageUsedCredits,
              let limit = overageMonthlyLimit,
              limit > 0 else { return nil }
        return (Double(used) / Double(limit)) * 100
    }

    var overageUsedFormatted: String? {
        guard let used = overageUsedCredits, let currency = overageCurrency else { return nil }
        return formatCurrency(amount: used, currency: currency)
    }

    var billableExtraUsageFormatted: String? {
        guard let used = overageUsedCredits,
              used > 0,
              let currency = overageCurrency else {
            return nil
        }

        let prepaidCoverage = effectivePrepaidCreditsTotal ?? effectivePrepaidCreditsRemaining
        let billableAmount = max(0, used - prepaidCoverage)
        guard billableAmount > 0 else { return nil }
        return formatCurrency(amount: billableAmount, currency: currency)
    }

    var billableExtraUsageWithCapFormatted: String? {
        guard let billable = billableExtraUsageFormatted else { return nil }
        guard let limit = overageMonthlyLimit,
              limit > 0,
              let currency = overageCurrency else {
            return billable
        }

        let amount = Double(limit) / 100.0
        return "\(billable) / \(String(format: "%.2f %@", amount, currency))"
    }

    private var effectivePrepaidCreditsRemaining: Int {
        let remaining = max(0, prepaidCreditsRemaining ?? 0)
        // Claude can return a one-cent residue for an empty prepaid balance.
        return remaining <= Self.cosmeticPrepaidResidueThresholdMinorUnits ? 0 : remaining
    }

    private var effectivePrepaidCreditsTotal: Int? {
        let remaining = effectivePrepaidCreditsRemaining
        guard remaining > 0 else { return nil }

        let declaredTotal = max(0, prepaidCreditsTotal ?? 0)
        let derivedTotal = remaining + max(0, overageUsedCredits ?? 0)
        return max(declaredTotal, derivedTotal, remaining)
    }

    var overageLimitFormatted: String? {
        guard let limit = overageMonthlyLimit,
              let currency = overageCurrency else { return nil }
        return formatCurrency(amount: limit, currency: currency)
    }

    var overageRemainingFormatted: String? {
        guard let limit = overageMonthlyLimit,
              let used = overageUsedCredits,
              let currency = overageCurrency else { return nil }
        return formatCurrency(amount: max(0, limit - used), currency: currency)
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        guard interval > 0 else { return "" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    nonisolated static let empty = UsageData(
        fiveHourUtilization: nil,
        fiveHourResetsAt: nil,
        sevenDayUtilization: nil,
        sevenDayResetsAt: nil,
        sevenDayOpusUtilization: nil,
        sevenDayOpusResetsAt: nil,
        sevenDaySonnetUtilization: nil,
        sevenDaySonnetResetsAt: nil,
        sevenDayScopedLabel: nil,
        sevenDayScopedUtilization: nil,
        sevenDayScopedResetsAt: nil,
        extraUsageUtilization: nil,
        extraUsageResetsAt: nil,
        planTier: .unknown,
        planDisplayNameOverride: nil,
        prepaidCreditsRemaining: nil,
        prepaidCreditsTotal: nil,
        prepaidCreditsCurrency: nil,
        prepaidAutoReloadEnabled: nil,
        overageMonthlyLimit: nil,
        overageUsedCredits: nil,
        overageCurrency: nil,
        overageEnabled: nil,
        overageOutOfCredits: nil
    )
}
