//
//  UsagePollingService.swift
//  PlanTracker
//

import Foundation

actor UsagePollingService {
    private enum PollingError: Error {
        case organizationUnavailable
    }

    private struct OrganizationContext: Sendable {
        let orgUuid: String
        let planTier: PlanTier
        let refreshedAt: Date
    }

    private struct BillingSnapshot: Sendable {
        let prepaidCreditsRemaining: Int?
        let prepaidCreditsTotal: Int?
        let prepaidCreditsCurrency: String?
        let prepaidAutoReloadEnabled: Bool?
        let overageMonthlyLimit: Int?
        let overageUsedCredits: Int?
        let overageCurrency: String?
        let overageEnabled: Bool?
        let overageOutOfCredits: Bool?
        let refreshedAt: Date
    }

    private let apiClient: ClaudeAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300
    private var organizationContext: OrganizationContext?
    private var billingSnapshot: BillingSnapshot?
    private var organizationRefreshInterval: TimeInterval = 6 * 3600
    private var billingRefreshInterval: TimeInterval = 3600

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
        pollingInterval = Swift.max(60, interval)
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

    func resetSteadyState() {
        organizationContext = nil
        billingSnapshot = nil
        billingRefreshInterval = 3600
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            billingRefreshInterval = max(billingRefreshInterval, 2 * 3600)
        case .critical:
            billingRefreshInterval = max(billingRefreshInterval, 6 * 3600)
        }
    }

    func fetchUsage(forceMetadataRefresh: Bool = false) async {
        do {
            let usageData = try await fetchUsageData(forceMetadataRefresh: forceMetadataRefresh)
            onUsageUpdate?(usageData)
        } catch {
            onError?(error)
        }
    }

    private func fetchUsageData(forceMetadataRefresh: Bool) async throws -> UsageData {
        let organization = try await resolveOrganizationContext(forceRefresh: forceMetadataRefresh)
        let usage = try await apiClient.fetchUsage(orgUuid: organization.orgUuid)
        let billing = try await resolveBillingSnapshot(
            orgUuid: organization.orgUuid,
            forceRefresh: forceMetadataRefresh
        )

        let fiveHourReset = usage.fiveHour?.resetsAt.flatMap(parseDate)
        let sevenDayReset = usage.sevenDay?.resetsAt.flatMap(parseDate)
        let sevenDayOpusReset = usage.sevenDayOpus?.resetsAt.flatMap(parseDate)
        let sevenDaySonnetReset = usage.sevenDaySonnet?.resetsAt.flatMap(parseDate)
        let extraUsageReset = usage.extraUsage?.resetsAt.flatMap(parseDate)

        let hasMonetaryOverage = {
            guard let billing else { return false }
            guard let monthlyLimit = billing.overageMonthlyLimit,
                  let usedCredits = billing.overageUsedCredits,
                  let currency = billing.overageCurrency else {
                return false
            }
            return monthlyLimit > 0 && usedCredits >= 0 && !currency.isEmpty
        }()

        let canonicalExtraUsageUtilization = hasMonetaryOverage ? nil : usage.extraUsage?.utilization
        let canonicalExtraUsageReset = hasMonetaryOverage ? nil : extraUsageReset
        let canonicalOverageEnabled: Bool? = hasMonetaryOverage ? true : billing?.overageEnabled

        return UsageData(
            fiveHourUtilization: usage.fiveHour?.utilization,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: usage.sevenDay?.utilization,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: usage.sevenDayOpus?.utilization,
            sevenDayOpusResetsAt: sevenDayOpusReset,
            sevenDaySonnetUtilization: usage.sevenDaySonnet?.utilization,
            sevenDaySonnetResetsAt: sevenDaySonnetReset,
            extraUsageUtilization: canonicalExtraUsageUtilization,
            extraUsageResetsAt: canonicalExtraUsageReset,
            planTier: organization.planTier,
            prepaidCreditsRemaining: billing?.prepaidCreditsRemaining,
            prepaidCreditsTotal: billing?.prepaidCreditsTotal,
            prepaidCreditsCurrency: billing?.prepaidCreditsCurrency,
            prepaidAutoReloadEnabled: billing?.prepaidAutoReloadEnabled,
            overageMonthlyLimit: billing?.overageMonthlyLimit,
            overageUsedCredits: billing?.overageUsedCredits,
            overageCurrency: billing?.overageCurrency,
            overageEnabled: canonicalOverageEnabled,
            overageOutOfCredits: billing?.overageOutOfCredits
        )
    }

    private func resolveOrganizationContext(forceRefresh: Bool) async throws -> OrganizationContext {
        if !forceRefresh,
           let organizationContext,
           Date().timeIntervalSince(organizationContext.refreshedAt) < organizationRefreshInterval {
            return organizationContext
        }

        do {
            let organizations = try await apiClient.fetchOrganizations()
            guard let org = organizations.first, let orgUuid = org.uuid, !orgUuid.isEmpty else {
                if let organizationContext {
                    return organizationContext
                }
                throw PollingError.organizationUnavailable
            }

            let resolved = OrganizationContext(
                orgUuid: orgUuid,
                planTier: determinePlanTier(from: organizations),
                refreshedAt: Date()
            )
            organizationContext = resolved
            return resolved
        } catch {
            if let organizationContext {
                return organizationContext
            }
            throw error
        }
    }

    private func resolveBillingSnapshot(orgUuid: String, forceRefresh: Bool) async throws -> BillingSnapshot? {
        if !forceRefresh,
           let billingSnapshot,
           Date().timeIntervalSince(billingSnapshot.refreshedAt) < billingRefreshInterval {
            return billingSnapshot
        }

        do {
            let prepaidCredits = try await apiClient.fetchPrepaidCredits(orgUuid: orgUuid)
            let creditGrant = try await apiClient.fetchOverageCreditGrant(orgUuid: orgUuid)
            let overageSpendLimit = try await apiClient.fetchOverageSpendLimit(orgUuid: orgUuid)

            var prepaidRemaining: Int?
            var prepaidTotal: Int?
            var prepaidCurrency: String?
            var autoReloadEnabled: Bool?

            if let prepaidCredits {
                prepaidRemaining = prepaidCredits.amount
                prepaidCurrency = prepaidCredits.currency
                autoReloadEnabled = prepaidCredits.autoReloadSettings?.enabled ?? false
                if let creditGrant, creditGrant.granted {
                    prepaidTotal = creditGrant.amountMinorUnits
                }
            }

            let resolved = BillingSnapshot(
                prepaidCreditsRemaining: prepaidRemaining,
                prepaidCreditsTotal: prepaidTotal,
                prepaidCreditsCurrency: prepaidCurrency,
                prepaidAutoReloadEnabled: autoReloadEnabled,
                overageMonthlyLimit: overageSpendLimit?.monthlyCreditLimit,
                overageUsedCredits: overageSpendLimit?.usedCredits,
                overageCurrency: overageSpendLimit?.currency,
                overageEnabled: overageSpendLimit?.isEnabled,
                overageOutOfCredits: overageSpendLimit?.outOfCredits,
                refreshedAt: Date()
            )
            billingSnapshot = resolved
            return resolved
        } catch {
            if let billingSnapshot {
                return billingSnapshot
            }
            throw error
        }
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
