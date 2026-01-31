//
//  AuthenticationService.swift
//  ClaudeMeter
//

import Foundation

actor AuthenticationService {
    private let keychainService: KeychainService
    private let apiClient: ClaudeAPIClient

    private let sessionKeyKey = "sessionKey"

    init(keychainService: KeychainService, apiClient: ClaudeAPIClient) {
        self.keychainService = keychainService
        self.apiClient = apiClient
    }

    func checkStoredCredentials() async -> AuthState {
        do {
            let sessionKey = try await keychainService.loadString(key: sessionKeyKey)
            await apiClient.setSessionKey(sessionKey)

            let bootstrap = try await apiClient.fetchBootstrap()
            if let email = bootstrap.account?.emailAddress {
                return .authenticated(email: email)
            }
            return .unauthenticated
        } catch KeychainService.KeychainError.itemNotFound {
            return .unauthenticated
        } catch ClaudeAPIClient.APIError.unauthorized, ClaudeAPIClient.APIError.forbidden {
            try? await clearCredentials()
            return .unauthenticated
        } catch {
            return .unauthenticated
        }
    }

    func saveSessionKey(_ sessionKey: String) async throws {
        try await keychainService.save(key: sessionKeyKey, string: sessionKey)
        await apiClient.setSessionKey(sessionKey)
    }

    func validateSession() async throws -> String {
        let bootstrap = try await apiClient.fetchBootstrap()
        guard let email = bootstrap.account?.emailAddress else {
            throw ClaudeAPIClient.APIError.unauthorized
        }
        return email
    }

    func clearCredentials() async throws {
        try await keychainService.delete(key: sessionKeyKey)
        await apiClient.clearSessionKey()
    }
}
