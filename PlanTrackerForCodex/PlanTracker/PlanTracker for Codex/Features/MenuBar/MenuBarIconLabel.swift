//
//  MenuBarIconLabel.swift
//  PlanTracker
//

import SwiftUI

struct MenuBarIconLabel: View {
    let usageData: UsageData
    let authState: AuthState
    let showRemainingPercent: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if let percentage = displayPercentage {
                Text(percentage)
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        guard authState.isAuthenticated else {
            return "gauge.with.needle.fill"
        }

        if let highWatermark = [
            usageData.fiveHourUtilization,
            usageData.sevenDayUtilization,
            usageData.sevenDayOpusUtilization,
            usageData.sevenDaySonnetUtilization,
            usageData.extraUsageUtilization
        ].compactMap({ $0 }).max(), highWatermark >= 97 {
            return "exclamationmark.circle.fill"
        }

        let remaining = usageData.fiveHourRemaining
            ?? usageData.sevenDayRemaining
            ?? usageData.sevenDayOpusRemaining
            ?? usageData.sevenDaySonnetRemaining
            ?? usageData.extraUsageRemaining

        guard let remaining else {
            return "gauge.with.needle.fill"
        }

        switch remaining {
        case 83...:
            return "gauge.with.needle.fill"
        case 67..<83:
            return "gauge.with.needle.fill"
        case 50..<67:
            return "gauge.with.needle.fill"
        case 17..<50:
            return "gauge.with.needle.fill"
        default:
            return "gauge.with.needle.fill"
        }
    }

    private var displayPercentage: String? {
        guard authState.isAuthenticated else { return nil }

        if showRemainingPercent {
            guard let remaining = usageData.fiveHourRemaining
                ?? usageData.sevenDayRemaining
                ?? usageData.sevenDayOpusRemaining
                ?? usageData.sevenDaySonnetRemaining
                ?? usageData.extraUsageRemaining else { return nil }
            return "\(Int(remaining))%"
        } else {
            guard let utilization = usageData.fiveHourUtilization
                ?? usageData.sevenDayUtilization
                ?? usageData.sevenDayOpusUtilization
                ?? usageData.sevenDaySonnetUtilization
                ?? usageData.extraUsageUtilization else { return nil }
            return "\(Int(utilization))%"
        }
    }
}
