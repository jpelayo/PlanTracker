//
//  PlanTrackerTests.swift
//  PlanTrackerTests
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import Foundation
import Testing
@testable import PlanTracker_for_Codex

struct PlanTrackerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func primaryWindowWithMultiDayResetMapsToWeeklySlot() async {
        let service = UsagePollingService(apiClient: OpenAIAPIClient())
        let reset = Date().addingTimeInterval(5 * 24 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(
                name: "primary_window",
                utilization: 48,
                resetsAt: reset
            )
        ])

        #expect(slots.first == nil)
        #expect(slots.second?.utilization == 48)
        #expect(slots.second?.resetsAt == reset)
    }

}
