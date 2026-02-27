//
//  UsageData.swift
//  PlanTracker
//

import Foundation

struct UsageData: Sendable, Equatable {
    let fiveHourUtilization: Double?
    let fiveHourResetsAt: Date?
    let sevenDayUtilization: Double?
    let sevenDayResetsAt: Date?
    let sevenDayOpusUtilization: Double?
    let sevenDayOpusResetsAt: Date?
    let sevenDayOpusName: String?
    let sevenDaySonnetUtilization: Double?
    let sevenDaySonnetResetsAt: Date?
    let sevenDaySonnetName: String?
    let extraUsageUtilization: Double?
    let extraUsageResetsAt: Date?
    let extraUsageName: String?
    let planTier: PlanTier
    let prepaidCreditsRemaining: Int?  // Minor units (cents)
    let prepaidCreditsTotal: Int?      // Minor units (cents)
    let prepaidCreditsCurrency: String?
    let prepaidAutoReloadEnabled: Bool?
    let overageMonthlyLimit: Int?      // Minor units (cents)
    let overageUsedCredits: Int?       // Minor units (cents)
    let overageCurrency: String?
    let overageEnabled: Bool?
    let overageOutOfCredits: Bool?

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

    var extraUsageRemaining: Double? {
        guard let util = extraUsageUtilization else { return nil }
        return 100 - util
    }

    var prepaidCreditsUtilization: Double? {
        guard let remaining = prepaidCreditsRemaining,
              let total = prepaidCreditsTotal,
              total > 0 else { return nil }
        let used = Double(total - remaining)
        return (used / Double(total)) * 100
    }

    var prepaidCreditsRemainingFormatted: String? {
        guard let remaining = prepaidCreditsRemaining,
              let currency = prepaidCreditsCurrency else { return nil }
        return formatCurrency(amount: remaining, currency: currency)
    }

    var prepaidCreditsTotalFormatted: String? {
        guard let total = prepaidCreditsTotal,
              let currency = prepaidCreditsCurrency else { return nil }
        return formatCurrency(amount: total, currency: currency)
    }

    var prepaidCreditsSpent: Int? {
        guard let remaining = prepaidCreditsRemaining,
              let total = prepaidCreditsTotal else { return nil }
        return total - remaining
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

    var formattedExtraUsageReset: String? {
        guard let date = extraUsageResetsAt else { return nil }
        return formatTimeRemaining(until: date)
    }

    var overageUtilization: Double? {
        guard let used = overageUsedCredits, let limit = overageMonthlyLimit, limit > 0 else { return nil }
        return (Double(used) / Double(limit)) * 100
    }

    var overageUsedFormatted: String? {
        guard let used = overageUsedCredits, let currency = overageCurrency else { return nil }
        return formatCurrency(amount: used, currency: currency)
    }

    var overageLimitFormatted: String? {
        guard let limit = overageMonthlyLimit, let currency = overageCurrency else { return nil }
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
        sevenDayOpusName: nil,
        sevenDaySonnetUtilization: nil,
        sevenDaySonnetResetsAt: nil,
        sevenDaySonnetName: nil,
        extraUsageUtilization: nil,
        extraUsageResetsAt: nil,
        extraUsageName: nil,
        planTier: .unknown,
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
