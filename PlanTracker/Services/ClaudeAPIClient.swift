//
//  ClaudeAPIClient.swift
//  PlanTracker
//

import Foundation

actor ClaudeAPIClient {
    private let baseURL = URL(string: "https://claude.ai")!
    private let session: URLSession
    private var sessionKey: String?

    enum APIError: Error, LocalizedError {
        case unauthorized
        case forbidden
        case networkError(Error)
        case invalidResponse
        case decodingError(Error)
        case noSessionKey

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Session expired. Please log in again."
            case .forbidden:
                "Access denied. Please log in again."
            case .networkError(let error):
                "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                "Invalid response from server."
            case .decodingError(let error):
                "Failed to parse response: \(error.localizedDescription)"
            case .noSessionKey:
                "Not authenticated. Please log in."
            }
        }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
        ]
        self.session = URLSession(configuration: config)
    }

    func setSessionKey(_ key: String) {
        self.sessionKey = key
    }

    func clearSessionKey() {
        self.sessionKey = nil
    }

    private func makeRequest(endpoint: String) throws -> URLRequest {
        guard let sessionKey else {
            throw APIError.noSessionKey
        }

        let url = baseURL.appending(path: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let cookieValue = sessionKey.contains("=") ? sessionKey : "sessionKey=\(sessionKey)"
        request.setValue(cookieValue, forHTTPHeaderField: "Cookie")

        print("[ClaudeAPIClient] Request to \(endpoint)")
        return request
    }

    func fetchBootstrap() async throws -> BootstrapResponse {
        let request = try makeRequest(endpoint: "/api/bootstrap")
        let (data, response) = try await performRequest(request)
        print("[ClaudeAPIClient] Bootstrap raw: \(String(data: data, encoding: .utf8) ?? "nil")")
        return try decode(BootstrapResponse.self, from: data, response: response)
    }

    func fetchOrganizations() async throws -> [Organization] {
        let request = try makeRequest(endpoint: "/api/organizations")
        let (data, response) = try await performRequest(request)
        print("[ClaudeAPIClient] Organizations raw: \(String(data: data, encoding: .utf8) ?? "nil")")
        return try decode([Organization].self, from: data, response: response)
    }

    /// Fetch usage data for an organization
    func fetchUsage(orgUuid: String) async throws -> UsageResponse {
        let request = try makeRequest(endpoint: "/api/organizations/\(orgUuid)/usage")
        let (data, response) = try await performRequest(request)
        print("[ClaudeAPIClient] Usage raw: \(String(data: data, encoding: .utf8) ?? "nil")")
        return try decode(UsageResponse.self, from: data, response: response)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            print("[ClaudeAPIClient] Response status: \(httpResponse.statusCode)")
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            print("[ClaudeAPIClient] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        switch response.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(type, from: data)
            } catch {
                print("[ClaudeAPIClient] Decode error: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse
        }
    }
}

// MARK: - Response Models

struct BootstrapResponse: Codable, Sendable {
    let account: Account?

    struct Account: Codable, Sendable {
        let uuid: String?
        let emailAddress: String?
        let displayName: String?
    }
}

struct Organization: Codable, Sendable {
    let uuid: String?
    let name: String?
    let rateLimitTier: String?
    let capabilities: [String]?
    let activeFlags: [String]?
    let settings: OrgSettings?

    struct OrgSettings: Codable, Sendable {
        let claudeConsolePrivacy: String?
    }
}

struct UsageResponse: Codable, Sendable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDayOpus: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?
    let sevenDayOauthApps: UsagePeriod?
    let sevenDayCowork: UsagePeriod?
    let iguanaNecktie: UsagePeriod?
    let extraUsage: UsagePeriod?

    struct UsagePeriod: Codable, Sendable {
        let utilization: Double
        let resetsAt: String?
    }
}

struct SettingsResponse: Codable, Sendable {
    let rateLimitInfo: RateLimitInfo?

    struct RateLimitInfo: Codable, Sendable {
        let messagesRemaining: Int?
        let messageLimit: Int?
        let resetsAt: String?
    }
}
