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
    private let apiClient: ClaudeAPIClient
    private let defaults = UserDefaults.standard

    private let sessionKeyKey = "sessionKey"
    private let cachedEmailKey = "auth.cachedAccountEmail"

    init(keychainService: KeychainService, apiClient: ClaudeAPIClient) {
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
        } catch ClaudeAPIClient.APIError.unauthorized, ClaudeAPIClient.APIError.forbidden {
            try? await clearCredentials()
            return .unauthenticated
        } catch {
            return .restoring(email: restoredSession.email)
        }
    }

    func restoreStoredSession() async -> RestoredSession? {
        do {
            let sessionKey = try await keychainService.loadString(key: sessionKeyKey)
            await apiClient.setSessionKey(sessionKey)
            return RestoredSession(email: defaults.string(forKey: cachedEmailKey))
        } catch KeychainService.KeychainError.itemNotFound {
            return nil
        } catch {
            return nil
        }
    }

    func saveSessionKey(_ sessionKey: String) async throws {
        try await keychainService.save(key: sessionKeyKey, string: sessionKey)
        await apiClient.setSessionKey(sessionKey)
    }

    func validateSession() async throws -> String {
        try await refreshCachedIdentity()
    }

    func refreshCachedIdentity() async throws -> String {
        let bootstrap = try await apiClient.fetchBootstrap()
        guard let email = bootstrap.account?.emailAddress else {
            throw ClaudeAPIClient.APIError.unauthorized
        }
        defaults.set(email, forKey: cachedEmailKey)
        return email
    }

    func clearCredentials() async throws {
        try await keychainService.delete(key: sessionKeyKey)
        await apiClient.clearSessionKey()
        defaults.removeObject(forKey: cachedEmailKey)
    }
}
