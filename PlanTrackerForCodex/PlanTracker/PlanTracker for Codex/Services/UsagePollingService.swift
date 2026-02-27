//
//  UsagePollingService.swift
//  PlanTracker
//

import Foundation

actor UsagePollingService {
    private let apiClient: OpenAIAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300 // 5 minutes default

    private var onUsageUpdate: (@Sendable (UsageData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    init(apiClient: OpenAIAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUsageUpdate: @escaping @Sendable (UsageData) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.onUsageUpdate = onUsageUpdate
        self.onError = onError
    }

    func setPollingInterval(_ interval: TimeInterval) {
        self.pollingInterval = Swift.max(60, interval)
    }

    func startPolling() {
        stopPolling()

        pollingTask = Task {
            while !Task.isCancelled {
                await fetchUsage()
                try? await Task.sleep(for: .seconds(pollingInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func fetchUsage() async {
        do {
            let usageData = try await fetchUsageData()
            onUsageUpdate?(usageData)
        } catch {
            print("[UsagePollingService] Error fetching usage: \(error)")
            onError?(error)
        }
    }

    private func fetchUsageData() async throws -> UsageData {
        async let profileTask = apiClient.fetchMeProfile()
        async let snapshotTask = apiClient.fetchUsageSnapshot()

        let snapshot = try await snapshotTask
        let profile = try? await profileTask

        let planLabel = profile?.planLabel ?? snapshot.planLabel
        let planTier = determinePlanTier(from: planLabel)
        let slots = mapLimitsToSlots(snapshot.limits)

        for limit in snapshot.limits.prefix(8) {
            print("[UsagePollingService] limit: \(limit.name) util=\(Int(limit.utilization)) reset=\(String(describing: limit.resetsAt))")
        }

        return UsageData(
            fiveHourUtilization: slots.first?.utilization,
            fiveHourResetsAt: slots.first?.resetsAt,
            sevenDayUtilization: slots.second?.utilization,
            sevenDayResetsAt: slots.second?.resetsAt,
            sevenDayOpusUtilization: slots.third?.utilization,
            sevenDayOpusResetsAt: slots.third?.resetsAt,
            sevenDayOpusName: displayName(for: slots.third),
            sevenDaySonnetUtilization: slots.fourth?.utilization,
            sevenDaySonnetResetsAt: slots.fourth?.resetsAt,
            sevenDaySonnetName: displayName(for: slots.fourth),
            extraUsageUtilization: slots.fifth?.utilization,
            extraUsageResetsAt: slots.fifth?.resetsAt,
            extraUsageName: displayName(for: slots.fifth),
            planTier: planTier,
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

    private func mapLimitsToSlots(_ limits: [OpenAIUsageLimit]) -> (
        first: OpenAIUsageLimit?,
        second: OpenAIUsageLimit?,
        third: OpenAIUsageLimit?,
        fourth: OpenAIUsageLimit?,
        fifth: OpenAIUsageLimit?
    ) {
        if limits.isEmpty {
            return (nil, nil, nil, nil, nil)
        }

        var remaining = limits
        var slots: [OpenAIUsageLimit?] = Array(repeating: nil, count: 5)

        let fixedNameToSlot: [String: Int] = [
            "primary_window": 0,
            "secondary_window": 1,
            "weekly_window": 1,
            "tertiary_window": 2,
            "quaternary_window": 3
        ]

        for (fixedName, slotIndex) in fixedNameToSlot where slots[slotIndex] == nil {
            slots[slotIndex] = popFirst(from: &remaining) {
                normalizedName(of: $0) == fixedName
            }
        }

        if slots[0] == nil {
            slots[0] = popBest(from: &remaining, minimumScore: 1, scoring: fiveHourScore)
        }
        if slots[1] == nil {
            slots[1] = popBest(from: &remaining, minimumScore: 1, scoring: sevenDayScore)
        }

        // Keep Code Review as the dedicated "extra" card when present.
        if slots[4] == nil {
            slots[4] = popBest(from: &remaining, minimumScore: 120, scoring: codeReviewScore)
        }

        // Remaining model/window buckets fill the two middle cards.
        if slots[2] == nil {
            slots[2] = popBest(from: &remaining, minimumScore: 1, scoring: modelFiveHourScore)
        }
        if slots[3] == nil {
            slots[3] = popBest(from: &remaining, minimumScore: 1, scoring: modelWeeklyScore)
        }

        let sortedRemainder = remaining.sorted(by: compareLimitOrder)
        var remainderIndex = 0
        for slotIndex in 0 ..< slots.count where slots[slotIndex] == nil {
            guard remainderIndex < sortedRemainder.count else { break }
            slots[slotIndex] = sortedRemainder[remainderIndex]
            remainderIndex += 1
        }

        return (
            slots[safe: 0] ?? nil,
            slots[safe: 1] ?? nil,
            slots[safe: 2] ?? nil,
            slots[safe: 3] ?? nil,
            slots[safe: 4] ?? nil
        )
    }

    private func popFirst(
        from limits: inout [OpenAIUsageLimit],
        where predicate: (OpenAIUsageLimit) -> Bool
    ) -> OpenAIUsageLimit? {
        guard let index = limits.firstIndex(where: predicate) else { return nil }
        return limits.remove(at: index)
    }

    private func popBest(
        from limits: inout [OpenAIUsageLimit],
        minimumScore: Int,
        scoring: (OpenAIUsageLimit) -> Int
    ) -> OpenAIUsageLimit? {
        guard !limits.isEmpty else { return nil }

        var bestIndex: Int?
        var bestScore = Int.min

        for (index, limit) in limits.enumerated() {
            let score = scoring(limit)
            guard score >= minimumScore else { continue }

            if let currentBestIndex = bestIndex {
                let currentBest = limits[currentBestIndex]
                if score > bestScore || (score == bestScore && compareLimitOrder(limit, currentBest)) {
                    bestIndex = index
                    bestScore = score
                }
            } else {
                bestIndex = index
                bestScore = score
            }
        }

        guard let bestIndex else { return nil }
        return limits.remove(at: bestIndex)
    }

    private func fiveHourScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        var score = 0

        if normalized == "primary_window" { score += 220 }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "five_hour", "hourly"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score += 80 }
        if containsAny(in: normalized, keywords: ["day", "week", "weekly"]) { score -= 90 }

        if let hours = hoursUntilReset(for: limit) {
            if hours > 0, hours <= 12 {
                score += 120
            } else if hours > 12, hours <= 36 {
                score += 20
            } else if hours > 36 {
                score -= 80
            }
        }

        return score
    }

    private func sevenDayScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        var score = 0

        if normalized == "secondary_window" || normalized == "weekly_window" { score += 220 }
        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score -= 90 }

        if let hours = hoursUntilReset(for: limit) {
            if hours >= 24, hours <= 240 {
                score += 120
            } else if hours > 0, hours < 16 {
                score -= 80
            } else if hours > 240 {
                score -= 20
            }
        }

        return score
    }

    private func codeReviewScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["code_review", "review_code", "codereview"]) {
            score += 260
        }
        if tokens.contains("review") || tokens.contains("revisar") {
            score += 120
        }
        if tokens.contains("code") || tokens.contains("codigo") || tokens.contains("codex") {
            score += 100
        }
        if tokens.contains("spark") {
            score -= 80
        }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "hourly", "7d", "7_day", "weekly"]) {
            score -= 20
        }

        return score
    }

    private func modelFiveHourScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "five_hour", "hourly"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score += 70 }
        if tokens.contains("spark") || tokens.contains("gpt") || tokens.contains("codex") { score += 40 }
        if codeReviewScore(limit) >= 120 { score -= 200 }
        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score -= 80 }

        if let hours = hoursUntilReset(for: limit) {
            if hours > 0, hours <= 12 {
                score += 100
            } else if hours > 12, hours <= 36 {
                score += 30
            } else if hours > 36 {
                score -= 60
            }
        }

        return score
    }

    private func modelWeeklyScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score += 180 }
        if tokens.contains("spark") || tokens.contains("gpt") || tokens.contains("codex") { score += 40 }
        if codeReviewScore(limit) >= 120 { score -= 200 }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "hourly", "hour"]) { score -= 80 }

        if let hours = hoursUntilReset(for: limit) {
            if hours >= 24, hours <= 240 {
                score += 100
            } else if hours > 0, hours < 16 {
                score -= 80
            }
        }

        return score
    }

    private func hoursUntilReset(for limit: OpenAIUsageLimit) -> Double? {
        guard let resetsAt = limit.resetsAt else { return nil }
        return resetsAt.timeIntervalSinceNow / 3600
    }

    private func normalizedName(of limit: OpenAIUsageLimit) -> String {
        let normalized = limit.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        return tokens.joined(separator: "_")
    }

    private func tokenSet(of limit: OpenAIUsageLimit) -> Set<String> {
        Set(normalizedName(of: limit).split(separator: "_").map(String.init))
    }

    private func containsAny(in value: String, keywords: [String]) -> Bool {
        keywords.contains(where: value.contains)
    }

    private func hasMeaningfulDisplayName(_ limit: OpenAIUsageLimit) -> Bool {
        displayName(for: limit) != nil
    }

    private func compareLimitOrder(_ lhs: OpenAIUsageLimit, _ rhs: OpenAIUsageLimit) -> Bool {
        let lhsMeaningful = hasMeaningfulDisplayName(lhs)
        let rhsMeaningful = hasMeaningfulDisplayName(rhs)
        if lhsMeaningful != rhsMeaningful {
            return lhsMeaningful && !rhsMeaningful
        }

        switch (lhs.resetsAt, rhs.resetsAt) {
        case let (l?, r?):
            if l != r { return l < r }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func displayName(for limit: OpenAIUsageLimit?) -> String? {
        guard let raw = limit?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let lowercased = raw.lowercased()
        let normalized = lowercased.replacingOccurrences(of: "-", with: "_")
        let genericNames = ["usage", "limit", "limits", "quota", "quotas", "data", "item", "items"]
        if genericNames.contains(lowercased) {
            return nil
        }

        // Hide backend/internal window identifiers so the UI uses friendlier fallbacks.
        if [
            "primary_window",
            "secondary_window",
            "tertiary_window",
            "quaternary_window",
            "weekly_window"
        ].contains(normalized) {
            return nil
        }

        return raw
    }

    private func determinePlanTier(from planLabel: String?) -> PlanTier {
        guard let planLabel else { return .unknown }
        let tier = planLabel.lowercased()
        if tier.contains("enterprise") { return .enterprise }
        if tier.contains("team") || tier.contains("business") { return .team }
        if tier.contains("pro") || tier.contains("plus") { return .pro }
        if tier.contains("max") { return .max }
        if tier.contains("free") { return .free }
        return .unknown
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
