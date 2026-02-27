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
    private(set) var authState: AuthState = .unknown {
        didSet {
            print("[UsageViewModel] authState changed to: \(authState)")
        }
    }
    private(set) var usageData: UsageData = .empty {
        didSet {
            print("[UsageViewModel] usageData changed - plan: \(usageData.planTier)")
        }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false

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
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[UsageViewModel] Failed to update login item: \(error)")
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
    private let apiClient: OpenAIAPIClient
    private let authService: AuthenticationService
    private let pollingService: UsagePollingService
    private let cookieManager: WebViewCookieManager

    init() {
        self.keychainService = KeychainService()
        self.apiClient = OpenAIAPIClient()
        self.authService = AuthenticationService(keychainService: keychainService, apiClient: apiClient)
        self.pollingService = UsagePollingService(apiClient: apiClient)
        self.cookieManager = WebViewCookieManager()

        let stored = UserDefaults.standard.integer(forKey: "pollingIntervalMinutes")
        if stored > 0 {
            self.pollingIntervalMinutes = Swift.min(Swift.max(stored, 1), 60)
        }

        if UserDefaults.standard.object(forKey: "showRemainingPercent") != nil {
            self.showRemainingPercent = UserDefaults.standard.bool(forKey: "showRemainingPercent")
        }

        self.launchAtLogin = SMAppService.mainApp.status == .enabled

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

        setupPollingCallbacks()
    }

    private func applyLanguage() {
        if let localeId = appLanguage.localeIdentifier {
            UserDefaults.standard.set([localeId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    private func setupPollingCallbacks() {
        Task {
            await pollingService.setCallbacks(
                onUsageUpdate: { [weak self] usage in
                    print("[UsageViewModel] Callback received usage update")
                    Task { @MainActor in
                        self?.usageData = usage
                        self?.lastUpdated = Date()
                        self?.errorMessage = nil
                        if self?.trackSessionTime == true {
                            self?.sessionTracker.processTick(
                                fiveHourUtilization: usage.fiveHourUtilization,
                                prepaidCreditsRemaining: usage.prepaidCreditsRemaining,
                                overageUsedCredits: usage.overageUsedCredits,
                                minInterval: TimeInterval((self?.sessionCheckIntervalMinutes ?? 5) * 60),
                                resetHour: self?.sessionResetHour ?? 4
                            )
                        }
                    }
                },
                onError: { [weak self] error in
                    print("[UsageViewModel] Callback received error: \(error)")
                    Task { @MainActor in
                        self?.handleError(error)
                    }
                }
            )
        }
    }

    func checkAuthentication() async {
        isLoading = true
        authState = .unknown

        // First, check if we have stored credentials in Keychain
        let state = await authService.checkStoredCredentials()

        if state.isAuthenticated {
            print("[UsageViewModel] Found valid session in Keychain")
            authState = state
            await startPolling()
            isLoading = false
            return
        }

        // If no Keychain credentials, check WebView cookies
        print("[UsageViewModel] No Keychain session, checking WebView cookies...")
        if let cookieString = await cookieManager.extractSessionCookies() {
            print("[UsageViewModel] Found WebView cookies, validating...")
            await handleLoginSuccess(sessionCookies: cookieString)
            isLoading = false
            return
        }

        print("[UsageViewModel] No valid session found")
        authState = .unauthenticated
        isLoading = false
    }

    func handleLoginSuccess(sessionCookies: String) async -> Bool {
        isLoading = true
        authState = .authenticating

        do {
            try await authService.saveSessionCookies(sessionCookies)
            let email = try await authService.validateSession()
            print("[UsageViewModel] Login validated, email: \(email)")
            authState = .authenticated(email: email)
            await startPolling()
            isLoading = false
            return true
        } catch {
            print("[UsageViewModel] Login validation failed: \(error)")
            handleError(error)
            authState = .unauthenticated
            isLoading = false
            return false
        }
    }

    func logout() async {
        print("[UsageViewModel] Logging out...")
        await pollingService.stopPolling()
        try? await authService.clearCredentials()

        // Also clear WebView cookies
        await cookieManager.clearSessionCookies()

        authState = .unauthenticated
        usageData = .empty
        lastUpdated = nil
        errorMessage = nil
        print("[UsageViewModel] Logged out successfully")
    }

    func refreshUsage() async {
        guard authState.isAuthenticated else { return }
        isLoading = true
        await pollingService.fetchUsage()
        isLoading = false
    }

    func activateDemoMode() {
        print("[UsageViewModel] Activating demo mode...")
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
            sevenDayOpusName: "Code Review",
            sevenDaySonnetUtilization: 81.2,
            sevenDaySonnetResetsAt: sevenDayReset,
            sevenDaySonnetName: "Additional Weekly Limit",
            extraUsageUtilization: 15.5,
            extraUsageResetsAt: sevenDayReset,
            extraUsageName: "Additional Limit",
            planTier: .pro,
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
        print("[UsageViewModel] Demo mode activated successfully")
    }

    private func startPolling() async {
        print("[UsageViewModel] Starting polling...")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
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
        if let apiError = error as? OpenAIAPIClient.APIError {
            switch apiError {
            case .unauthorized, .forbidden:
                Task {
                    await logout()
                }
                errorMessage = apiError.errorDescription
            default:
                errorMessage = apiError.errorDescription
            }
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
