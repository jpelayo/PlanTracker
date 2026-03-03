//
//  AuthenticationService.swift
//  PlanTracker
//

import Foundation

actor AuthenticationService {
    struct RestoredSession: Sendable {
        let email: String?
    }

    private let keychainService: KeychainService
    private let apiClient: OpenAIAPIClient
    private let defaults = UserDefaults.standard

    private let sessionCookiesKey = "openaiSessionCookies"
    private let cachedEmailKey = "auth.cachedAccountEmail"

    init(keychainService: KeychainService, apiClient: OpenAIAPIClient) {
        self.keychainService = keychainService
        self.apiClient = apiClient
    }

    func checkStoredCredentials() async -> AuthState {
        guard let restoredSession = await restoreStoredSession() else {
            return .unauthenticated
        }

        do {
            let email = try await refreshCachedIdentity()
            return .authenticated(email: email)
        } catch OpenAIAPIClient.APIError.unauthorized, OpenAIAPIClient.APIError.forbidden {
            try? await clearCredentials()
            return .unauthenticated
        } catch {
            return .restoring(email: restoredSession.email)
        }
    }

    func restoreStoredSession() async -> RestoredSession? {
        do {
            let sessionCookies = try await keychainService.loadString(key: sessionCookiesKey)
            await apiClient.setSessionCookies(sessionCookies)
            return RestoredSession(email: defaults.string(forKey: cachedEmailKey))
        } catch KeychainService.KeychainError.itemNotFound {
            return nil
        } catch {
            return nil
        }
    }

    func saveSessionCookies(_ sessionCookies: String) async throws {
        try await keychainService.save(key: sessionCookiesKey, string: sessionCookies)
        await apiClient.setSessionCookies(sessionCookies)
    }

    func validateSession() async throws -> String {
        try await refreshCachedIdentity(forceRefresh: true)
    }

    func refreshCachedIdentity(forceRefresh: Bool = false) async throws -> String {
        let profile = try await apiClient.fetchMeProfile(forceRefresh: forceRefresh)
        guard let identity = profile.email ?? profile.displayName else {
            throw OpenAIAPIClient.APIError.unauthorized
        }
        defaults.set(identity, forKey: cachedEmailKey)
        return identity
    }

    func clearCredentials() async throws {
        try await keychainService.delete(key: sessionCookiesKey)
        await apiClient.clearSessionCookies()
        defaults.removeObject(forKey: cachedEmailKey)
    }
}
