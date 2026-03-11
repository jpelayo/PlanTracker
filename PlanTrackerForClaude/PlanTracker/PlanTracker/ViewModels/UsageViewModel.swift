//
//  UsageViewModel.swift
//  PlanTracker
//

import Foundation
import SwiftUI
import ServiceManagement

@MainActor
@Observable
final class UsageViewModel {
    private(set) var authState: AuthState = .unknown
    private(set) var usageData: UsageData = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false
    private(set) var claudeSystemStatus: ClaudeSystemStatus = .degraded
    private(set) var claudeStatusSourceUpdatedAt: Date?
    private let snapshotStore = PersistedUsageSnapshotStore()
    private var observerTokens: [NSObjectProtocol] = []
    private let loginItemService = SMAppService.loginItem(identifier: LoginItemConfiguration.helperBundleIdentifier)
    private var isApplyingLaunchAtLoginState = false
    private var isFetchingClaudeStatus = false
    private var lastClaudeStatusFetchAt: Date?
    private let claudeStatusRefreshInterval: TimeInterval = 5 * 60
    private let claudeStatusSignalWindow: TimeInterval = 24 * 60 * 60

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            UserDefaults.standard.set(pollingIntervalMinutes, forKey: "pollingIntervalMinutes")
            Task {
                await pollingService.setPollingInterval(TimeInterval(pollingIntervalMinutes * 60))
            }
        }
    }

    var showRemainingPercent: Bool = true {
        didSet {
            UserDefaults.standard.set(showRemainingPercent, forKey: "showRemainingPercent")
        }
    }

    var launchAtLogin: Bool = false {
        didSet {
            guard !isApplyingLaunchAtLoginState else { return }
            let requestedValue = launchAtLogin
            Task { @MainActor [weak self] in
                await self?.applyLaunchAtLoginChange(requestedValue)
            }
        }
    }

    var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            applyLanguage()
        }
    }

    var trackSessionTime: Bool = false {
        didSet {
            UserDefaults.standard.set(trackSessionTime, forKey: "trackSessionTime")
        }
    }

    var sessionCheckIntervalMinutes: Int = 5 {
        didSet {
            UserDefaults.standard.set(sessionCheckIntervalMinutes, forKey: "sessionCheckIntervalMinutes")
        }
    }

    var sessionResetHour: Int = 4 {
        didSet {
            UserDefaults.standard.set(sessionResetHour, forKey: "sessionResetHour")
        }
    }

    let sessionTracker = SessionTracker()

    private let keychainService: KeychainService
    private let apiClient: ClaudeAPIClient
    private let authService: AuthenticationService
    private let pollingService: UsagePollingService
    private let cookieManager: WebViewCookieManager
    private let claudeStatusService: ClaudeStatusService

    init() {
        self.keychainService = KeychainService()
        self.apiClient = ClaudeAPIClient()
        self.authService = AuthenticationService(keychainService: keychainService, apiClient: apiClient)
        self.pollingService = UsagePollingService(apiClient: apiClient)
        self.cookieManager = WebViewCookieManager()
        self.claudeStatusService = ClaudeStatusService()

        let launchState = AppRuntimeState.beginLaunchIfNeeded()
        if launchState.wasUnexpectedTermination {
            AppRuntimeState.recordBreadcrumb("unexpected-termination-detected")
        }
        CacheJanitor.prepareForLaunch()

        let stored = UserDefaults.standard.integer(forKey: "pollingIntervalMinutes")
        if stored > 0 {
            self.pollingIntervalMinutes = Swift.min(Swift.max(stored, 1), 60)
        }

        if UserDefaults.standard.object(forKey: "showRemainingPercent") != nil {
            self.showRemainingPercent = UserDefaults.standard.bool(forKey: "showRemainingPercent")
        }

        syncLaunchAtLoginFromSystem()

        if let storedLanguage = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: storedLanguage) {
            self.appLanguage = language
        }
        applyLanguage()

        if UserDefaults.standard.object(forKey: "trackSessionTime") != nil {
            self.trackSessionTime = UserDefaults.standard.bool(forKey: "trackSessionTime")
        }

        let storedCheckInterval = UserDefaults.standard.integer(forKey: "sessionCheckIntervalMinutes")
        if storedCheckInterval > 0 {
            self.sessionCheckIntervalMinutes = storedCheckInterval
        }

        let storedResetHour = UserDefaults.standard.integer(forKey: "sessionResetHour")
        if UserDefaults.standard.object(forKey: "sessionResetHour") != nil {
            self.sessionResetHour = storedResetHour
        }

        restorePersistedSnapshot()
        setupPollingCallbacks()
        observeLifecycleNotifications()
        Task { [weak self] in
            await self?.refreshClaudeStatus(force: true)
        }
    }

    private func applyLanguage() {
        if let localeId = appLanguage.localeIdentifier {
            UserDefaults.standard.set([localeId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    private func syncLaunchAtLoginFromSystem() {
        setLaunchAtLogin(loginItemService.status.isEnabledForUI)
        LoginItemSharedState.setHelperEnabled(launchAtLogin)
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        isApplyingLaunchAtLoginState = true
        launchAtLogin = isEnabled
        isApplyingLaunchAtLoginState = false
    }

    private func applyLaunchAtLoginChange(_ isEnabled: Bool) async {
        LoginItemSharedState.setHelperEnabled(isEnabled)
        do {
            if isEnabled {
                try loginItemService.register()
            } else {
                try await loginItemService.unregister()
            }
            syncLaunchAtLoginFromSystem()
        } catch {
            syncLaunchAtLoginFromSystem()
        }
    }

    private func setupPollingCallbacks() {
        Task {
            await pollingService.setCallbacks(
                onUsageUpdate: { [weak self] usage in
                    Task { @MainActor in
                        guard let self else { return }
                        let usageChanged = self.usageData != usage
                        self.usageData = usage
                        self.lastUpdated = Date()
                        self.errorMessage = nil
                        if self.trackSessionTime {
                            self.sessionTracker.processTick(
                                fiveHourUtilization: usage.fiveHourUtilization,
                                prepaidCreditsRemaining: usage.prepaidCreditsRemaining,
                                overageUsedCredits: usage.overageUsedCredits,
                                minInterval: TimeInterval(self.sessionCheckIntervalMinutes * 60),
                                resetHour: self.sessionResetHour
                            )
                        }
                        if usageChanged {
                            self.persistUsageSnapshot()
                        }
                    }
                    Task { [weak self] in
                        await self?.refreshClaudeStatus(force: false)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.handleError(error)
                    }
                }
            )
        }
    }

    private func observeLifecycleNotifications() {
        let center = NotificationCenter.default
        observerTokens.append(
            center.addObserver(forName: .planTrackerMemoryPressure, object: nil, queue: .main) { [weak self] notification in
                guard let level = notification.object as? AppMemoryPressureLevel else { return }
                Task { @MainActor in
                    await self?.handleMemoryPressure(level)
                }
            }
        )
    }

    func checkAuthentication() async {
        isLoading = true
        authState = .unknown
        AppRuntimeState.recordBreadcrumb("check-authentication")

        if let restoredSession = await authService.restoreStoredSession() {
            AppRuntimeState.recordBreadcrumb("auth-restored-keychain")
            authState = .restoring(email: restoredSession.email)
            errorMessage = nil
            await startPolling()
            isLoading = false
            Task { [weak self] in
                await self?.refreshRestoredIdentity()
            }
            return
        }

        if let cookieString = await cookieManager.extractSessionCookies() {
            AppRuntimeState.recordBreadcrumb("auth-restored-webview")
            await handleLoginSuccess(sessionKey: cookieString)
            isLoading = false
            return
        }

        AppRuntimeState.recordBreadcrumb("auth-missing")
        authState = .unauthenticated
        isLoading = false
    }

    private func refreshRestoredIdentity() async {
        do {
            let email = try await authService.refreshCachedIdentity()
            guard authState.isAuthenticated else { return }
            AppRuntimeState.recordBreadcrumb("auth-identity-refreshed")
            authState = .authenticated(email: email)
        } catch let error as ClaudeAPIClient.APIError {
            switch error {
            case .unauthorized, .forbidden:
                handleError(error)
            default:
                break
            }
        } catch {}
    }

    func handleLoginSuccess(sessionKey: String) async {
        isLoading = true
        authState = .authenticating

        do {
            try await authService.saveSessionKey(sessionKey)
            let email = try await authService.validateSession()
            AppRuntimeState.recordBreadcrumb("login-success")
            authState = .authenticated(email: email)
            await startPolling()
        } catch {
            handleError(error)
            authState = .unauthenticated
        }

        isLoading = false
    }

    func logout() async {
        AppRuntimeState.recordBreadcrumb("logout")
        await pollingService.stopPolling()
        await pollingService.resetSteadyState()
        try? await authService.clearCredentials()

        // Also clear WebView cookies
        await cookieManager.clearSessionCookies()

        authState = .unauthenticated
        usageData = .empty
        lastUpdated = nil
        errorMessage = nil
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "logout")
    }

    func refreshUsage() async {
        guard authState.isAuthenticated else { return }
        AppRuntimeState.recordBreadcrumb("manual-refresh")
        isLoading = true
        await pollingService.fetchUsage(forceMetadataRefresh: true)
        await refreshClaudeStatus(force: true)
        isLoading = false
    }

    func activateDemoMode() {
        isDemoMode = true
        authState = .authenticated(email: "demo@example.com")

        // Create realistic mock data
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(3 * 3600) // 3 hours from now
        let sevenDayReset = now.addingTimeInterval(4 * 24 * 3600) // 4 days from now

        usageData = UsageData(
            fiveHourUtilization: 42.0,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: 67.5,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: 23.0,
            sevenDayOpusResetsAt: sevenDayReset,
            sevenDaySonnetUtilization: 81.2,
            sevenDaySonnetResetsAt: sevenDayReset,
            extraUsageUtilization: 15.5,
            extraUsageResetsAt: sevenDayReset,
            planTier: .pro,
            planDisplayNameOverride: nil,
            prepaidCreditsRemaining: 4280,  // $42.80
            prepaidCreditsTotal: 5000,      // $50.00
            prepaidCreditsCurrency: "USD",
            prepaidAutoReloadEnabled: false,
            overageMonthlyLimit: 5000,      // $50.00
            overageUsedCredits: 1359,       // $13.59
            overageCurrency: "USD",
            overageEnabled: true,
            overageOutOfCredits: false
        )

        lastUpdated = now
        errorMessage = nil
        sessionTracker.setMockAccumulated(83 * 60) // 1h 23m
        persistUsageSnapshot()
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("start-polling")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
        await refreshClaudeStatus(force: true)
    }

    var displayedClaudeSystemStatus: ClaudeSystemStatus {
        guard let status = visibleClaudeSystemStatus else {
            return .operational
        }
        return status
    }

    var visibleClaudeSystemStatus: ClaudeSystemStatus? {
        guard let sourceUpdatedAt = claudeStatusSourceUpdatedAt else {
            return nil
        }
        guard isUsableClaudeStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        switch claudeSystemStatus {
        case .operational:
            return nil
        case .degraded, .outage:
            return claudeSystemStatus
        }
    }

    var visibleClaudeStatusSourceUpdatedAt: Date? {
        guard let sourceUpdatedAt = claudeStatusSourceUpdatedAt else {
            return nil
        }
        guard isUsableClaudeStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        return sourceUpdatedAt
    }

    var dailySessionFormatted: String? {
        guard trackSessionTime else { return nil }
        let s = sessionTracker.totalSeconds
        guard s >= 60 else { return nil }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let time = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return String(localized: "Today's usage:") + " " + time
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? ClaudeAPIClient.APIError {
            switch apiError {
            case .unauthorized, .forbidden:
                Task {
                    await logout()
                }
                errorMessage = apiError.errorDescription
            default:
                setNonCriticalErrorMessage(apiError.errorDescription)
            }
        } else {
            setNonCriticalErrorMessage(error.localizedDescription)
        }
    }

    private func setNonCriticalErrorMessage(_ message: String?) {
        guard shouldShowNonCriticalError else {
            errorMessage = nil
            return
        }
        errorMessage = message
    }

    private var shouldShowNonCriticalError: Bool {
        if case .authenticating = authState {
            return true
        }
        return usageData == .empty && lastUpdated == nil
    }

    private func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        AppRuntimeState.recordBreadcrumb("view-model-memory-pressure-\(level.rawValue)")

        guard authState.isAuthenticated else { return }
        await pollingService.handleMemoryPressure(level)
    }

    private func restorePersistedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        usageData = snapshot.usageData
        lastUpdated = snapshot.lastUpdated
        AppRuntimeState.recordBreadcrumb("snapshot-restored")
    }

    private func persistUsageSnapshot() {
        snapshotStore.save(usageData: usageData, lastUpdated: lastUpdated)
    }

    private func refreshClaudeStatus(force: Bool) async {
        let now = Date()
        if !force,
           let lastFetch = lastClaudeStatusFetchAt,
           now.timeIntervalSince(lastFetch) < claudeStatusRefreshInterval {
            return
        }

        guard !isFetchingClaudeStatus else { return }
        isFetchingClaudeStatus = true
        lastClaudeStatusFetchAt = now
        defer { isFetchingClaudeStatus = false }

        do {
            let snapshot = try await claudeStatusService.fetchStatus()
            if let incomingUpdatedAt = snapshot.sourceUpdatedAt,
               let existingUpdatedAt = claudeStatusSourceUpdatedAt,
               incomingUpdatedAt < existingUpdatedAt {
                return
            }
            if snapshot.sourceUpdatedAt == nil, claudeStatusSourceUpdatedAt != nil {
                return
            }
            claudeSystemStatus = snapshot.status
            claudeStatusSourceUpdatedAt = snapshot.sourceUpdatedAt
        } catch {
            // Keep previous status value on transient failures.
        }
    }

    private func isUsableClaudeStatusTimestamp(_ sourceUpdatedAt: Date) -> Bool {
        let now = Date()
        if sourceUpdatedAt > now.addingTimeInterval(120) {
            return false
        }
        return now.timeIntervalSince(sourceUpdatedAt) <= claudeStatusSignalWindow
    }
}

private struct PersistedUsageSnapshot: Codable {
    let usageData: UsageData
    let lastUpdated: Date?
    let savedAt: Date
}

private struct PersistedUsageSnapshotStore {
    private let defaults = UserDefaults.standard
    private let key = "persistedUsageSnapshot.v1"

    func load() -> PersistedUsageSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedUsageSnapshot.self, from: data)
    }

    func save(usageData: UsageData, lastUpdated: Date?) {
        guard usageData != .empty else {
            clear()
            return
        }

        let snapshot = PersistedUsageSnapshot(
            usageData: usageData,
            lastUpdated: lastUpdated,
            savedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
