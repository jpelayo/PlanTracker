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
            extraUsageUtilization: slots.fifth?.utilization,
            extraUsageResetsAt: slots.fifth?.resetsAt,
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

        let sorted = limits.sorted { lhs, rhs in
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

        return (
            sorted[safe: 0],
            sorted[safe: 1],
            sorted[safe: 2],
            sorted[safe: 3],
            sorted[safe: 4]
        )
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
