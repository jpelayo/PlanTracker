//
//  AuthenticationService.swift
//  PlanTracker
//

import Foundation

actor AuthenticationService {
    private let keychainService: KeychainService
    private let apiClient: OpenAIAPIClient

    private let sessionCookiesKey = "openaiSessionCookies"

    init(keychainService: KeychainService, apiClient: OpenAIAPIClient) {
        self.keychainService = keychainService
        self.apiClient = apiClient
    }

    func checkStoredCredentials() async -> AuthState {
        do {
            let sessionCookies = try await keychainService.loadString(key: sessionCookiesKey)
            await apiClient.setSessionCookies(sessionCookies)

            let profile = try await apiClient.fetchMeProfile()
            if let email = profile.email ?? profile.displayName {
                return .authenticated(email: email)
            }
            return .unauthenticated
        } catch KeychainService.KeychainError.itemNotFound {
            return .unauthenticated
        } catch OpenAIAPIClient.APIError.unauthorized, OpenAIAPIClient.APIError.forbidden {
            try? await clearCredentials()
            return .unauthenticated
        } catch {
            return .unauthenticated
        }
    }

    func saveSessionCookies(_ sessionCookies: String) async throws {
        try await keychainService.save(key: sessionCookiesKey, string: sessionCookies)
        await apiClient.setSessionCookies(sessionCookies)
    }

    func validateSession() async throws -> String {
        let profile = try await apiClient.fetchMeProfile()
        guard let identity = profile.email ?? profile.displayName else {
            throw OpenAIAPIClient.APIError.unauthorized
        }
        return identity
    }

    func clearCredentials() async throws {
        try await keychainService.delete(key: sessionCookiesKey)
        await apiClient.clearSessionCookies()
    }
}
