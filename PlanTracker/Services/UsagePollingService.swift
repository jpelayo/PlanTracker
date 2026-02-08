//
//  UsagePollingService.swift
//  PlanTracker
//

import Foundation

actor UsagePollingService {
    private let apiClient: ClaudeAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300 // 5 minutes default

    private var onUsageUpdate: (@Sendable (UsageData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    init(apiClient: ClaudeAPIClient) {
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
        self.pollingInterval = Swift.max(60, interval) // Minimum 1 minute
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
        // Get organizations to find the org UUID and plan tier
        let organizations = try await apiClient.fetchOrganizations()

        guard let org = organizations.first, let orgUuid = org.uuid else {
            print("[UsagePollingService] No organization found")
            return .empty
        }

        let planTier = determinePlanTier(from: organizations)
        print("[UsagePollingService] Plan tier: \(planTier), Org UUID: \(orgUuid)")

        // Fetch usage data
        let usage = try await apiClient.fetchUsage(orgUuid: orgUuid)

        let fiveHourReset = usage.fiveHour?.resetsAt.flatMap { parseDate($0) }
        let sevenDayReset = usage.sevenDay?.resetsAt.flatMap { parseDate($0) }
        let sevenDayOpusReset = usage.sevenDayOpus?.resetsAt.flatMap { parseDate($0) }
        let sevenDaySonnetReset = usage.sevenDaySonnet?.resetsAt.flatMap { parseDate($0) }

        print("[UsagePollingService] 5h utilization: \(usage.fiveHour?.utilization ?? -1)%, resets: \(usage.fiveHour?.resetsAt ?? "nil")")
        print("[UsagePollingService] 7d utilization: \(usage.sevenDay?.utilization ?? -1)%, resets: \(usage.sevenDay?.resetsAt ?? "nil")")
        print("[UsagePollingService] 7d Opus utilization: \(usage.sevenDayOpus?.utilization ?? -1)%, resets: \(usage.sevenDayOpus?.resetsAt ?? "nil")")
        print("[UsagePollingService] 7d Sonnet utilization: \(usage.sevenDaySonnet?.utilization ?? -1)%, resets: \(usage.sevenDaySonnet?.resetsAt ?? "nil")")

        return UsageData(
            fiveHourUtilization: usage.fiveHour?.utilization,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: usage.sevenDay?.utilization,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: usage.sevenDayOpus?.utilization,
            sevenDayOpusResetsAt: sevenDayOpusReset,
            sevenDaySonnetUtilization: usage.sevenDaySonnet?.utilization,
            sevenDaySonnetResetsAt: sevenDaySonnetReset,
            planTier: planTier
        )
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func determinePlanTier(from organizations: [Organization]?) -> PlanTier {
        guard let org = organizations?.first else {
            return .unknown
        }

        if let tier = org.rateLimitTier?.lowercased() {
            if tier.contains("max") { return .max }
            if tier.contains("pro") { return .pro }
            if tier.contains("team") { return .team }
            if tier.contains("enterprise") { return .enterprise }
            if tier.contains("free") { return .free }
        }

        if let capabilities = org.capabilities {
            if capabilities.contains(where: { $0.lowercased().contains("max") }) {
                return .max
            } else if capabilities.contains(where: { $0.lowercased().contains("pro") }) {
                return .pro
            }
        }

        return .unknown
    }
}
