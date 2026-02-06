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
            return "gauge.with.dots.needle.50percent"
        }

        guard let remaining = usageData.fiveHourRemaining else {
            return "gauge.with.dots.needle.50percent"
        }

        switch remaining {
        case 83...:
            return "gauge.with.dots.needle.100percent"
        case 67..<83:
            return "gauge.with.dots.needle.67percent"
        case 50..<67:
            return "gauge.with.dots.needle.50percent"
        case 17..<50:
            return "gauge.with.dots.needle.33percent"
        default:
            return "gauge.with.dots.needle.0percent"
        }
    }

    private var displayPercentage: String? {
        guard authState.isAuthenticated else {
            return nil
        }

        if showRemainingPercent {
            guard let remaining = usageData.fiveHourRemaining else { return nil }
            return "\(Int(remaining))%"
        } else {
            guard let utilization = usageData.fiveHourUtilization else { return nil }
            return "\(Int(utilization))%"
        }
    }
}
