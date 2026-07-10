//
//  PlanTrackerTests.swift
//  PlanTrackerTests
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import Foundation
import Testing
@testable import PlanTracker

struct PlanTrackerTests {

    @Test func oneCentPrepaidResidueIsHidden() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 1,
            prepaidCreditsTotal: 1,
            prepaidCreditsCurrency: "USD",
            prepaidAutoReloadEnabled: false,
            overageMonthlyLimit: 500,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasAvailablePrepaidCredits == false)
        #expect(usage.prepaidCreditsRemainingFormatted == nil)
        #expect(usage.prepaidCreditsTotalFormatted == nil)
        #expect(usage.prepaidCreditsSpentFormatted == nil)
        #expect(usage.prepaidCreditsUtilization == nil)
    }

    @Test func prepaidCreditAboveResidueThresholdIsVisibleAtZeroUsage() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 2,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: false
        )

        #expect(usage.hasAvailablePrepaidCredits == true)
        #expect(usage.prepaidCreditsRemainingFormatted == "0.02 USD")
        #expect(usage.prepaidCreditsUtilization == 0)
    }

    @Test func oneCentPrepaidResidueDoesNotOffsetBillableExtraSpend() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 1,
            prepaidCreditsTotal: 1,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: 500,
            overageUsedCredits: 125,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.billableExtraUsageFormatted == "1.25 USD")
        #expect(usage.billableExtraUsageWithCapFormatted == "1.25 USD / 5.00 USD")
    }

    @Test func prepaidBalanceWithoutGrantTotalStillHasProgressDenominator() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 20001,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasAvailablePrepaidCredits == true)
        #expect(usage.prepaidCreditsRemainingFormatted == "200.01 USD")
        #expect(usage.prepaidCreditsTotalFormatted == "200.01 USD")
        #expect(usage.prepaidCreditsSpentFormatted == "0.00 USD")
        #expect(usage.prepaidCreditsUtilization == 0)
    }

    @Test func freeCreditConsumptionIsNotShownAsBillableExtraSpend() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 19501,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: 500,
            overageUsedCredits: 500,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.prepaidCreditsTotalFormatted == "200.01 USD")
        #expect(usage.prepaidCreditsSpentFormatted == "5.00 USD")
        #expect(usage.billableExtraUsageFormatted == nil)
        #expect(usage.billableExtraUsageWithCapFormatted == nil)
    }

    @Test func claudeUsageDecodesDisabledExtraSpendControlObject() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 22.0,
            "resets_at": "2026-07-09T14:30:00.039431+00:00"
          },
          "seven_day": {
            "utilization": 84.0,
            "resets_at": "2026-07-10T04:00:00.039459+00:00"
          },
          "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": null,
            "utilization": null,
            "currency": null,
            "decimal_places": null
          },
          "limits": [
            {
              "kind": "weekly_scoped",
              "group": "weekly",
              "percent": 99,
              "resets_at": "2026-07-10T04:00:00.039948+00:00",
              "scope": {
                "model": {
                  "id": null,
                  "display_name": "Fable"
                },
                "surface": null
              },
              "is_active": true
            }
          ],
          "spend": {
            "used": {
              "amount_minor": 0,
              "currency": "USD",
              "exponent": 2
            },
            "limit": null,
            "percent": 0,
            "severity": "normal",
            "enabled": false,
            "cap": null,
            "balance": null,
            "auto_reload": null
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(UsageResponse.self, from: Data(json.utf8))

        #expect(response.extraUsage == nil)
        #expect(response.extraUsageEnabled == false)
        #expect(response.spend?.enabled == false)
        #expect(response.spend?.limit == nil)
        #expect(response.sevenDayScoped?.label == "Fable")
        #expect(response.sevenDayScoped?.period.utilization == 99)
    }

    private func makeUsageData(
        prepaidCreditsRemaining: Int?,
        prepaidCreditsTotal: Int?,
        prepaidCreditsCurrency: String?,
        prepaidAutoReloadEnabled: Bool? = nil,
        overageMonthlyLimit: Int?,
        overageUsedCredits: Int?,
        overageCurrency: String?,
        overageEnabled: Bool?
    ) -> UsageData {
        UsageData(
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
            planTier: .max,
            planDisplayNameOverride: "Max (20x)",
            prepaidCreditsRemaining: prepaidCreditsRemaining,
            prepaidCreditsTotal: prepaidCreditsTotal,
            prepaidCreditsCurrency: prepaidCreditsCurrency,
            prepaidAutoReloadEnabled: prepaidAutoReloadEnabled,
            overageMonthlyLimit: overageMonthlyLimit,
            overageUsedCredits: overageUsedCredits,
            overageCurrency: overageCurrency,
            overageEnabled: overageEnabled,
            overageOutOfCredits: nil
        )
    }
}
