//
//  ClaudeAPIClient.swift
//  PlanTracker
//

import Foundation

actor OpenAIAPIClient {
    private let baseURL = URL(string: "https://chatgpt.com")!
    private let session: URLSession
    private var sessionCookies: String?
    private var accessToken: String?

    enum APIError: Error, LocalizedError {
        case unauthorized
        case forbidden
        case networkError(Error)
        case invalidResponse
        case decodingError(Error)
        case noSessionCookies
        case usageDataUnavailable

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Session expired. Please sign in again."
            case .forbidden:
                "Access denied. Please sign in again."
            case .networkError(let error):
                "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                "Invalid response from server."
            case .decodingError(let error):
                "Failed to parse response: \(error.localizedDescription)"
            case .noSessionCookies:
                "Not authenticated. Please sign in."
            case .usageDataUnavailable:
                "OpenAI usage limits are not available for this account or response format."
            }
        }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Origin": "https://chatgpt.com",
            "Referer": "https://chatgpt.com/"
        ]
        self.session = URLSession(configuration: config)
    }

    func setSessionCookies(_ cookies: String) {
        self.sessionCookies = cookies
    }

    func clearSessionCookies() {
        self.sessionCookies = nil
        self.accessToken = nil
    }

    func fetchSession() async throws -> OpenAISessionResponse {
        let request = try makeRequest(endpoint: "/api/auth/session")
        let (data, response) = try await performRequest(request)
        let sessionResponse = try decode(OpenAISessionResponse.self, from: data, response: response)

        if let token = sessionResponse.accessToken, !token.isEmpty {
            accessToken = token
        }

        return sessionResponse
    }

    func fetchMeProfile() async throws -> OpenAIMeProfile {
        _ = try await fetchSession()
        let request = try makeRequest(endpoint: "/backend-api/me", includeAuthorization: true)
        let (data, response) = try await performRequest(request)
        let json = try decodeJSON(from: data, response: response)
        return OpenAIMeParser.parseProfile(from: json)
    }

    func fetchUsageSnapshot() async throws -> OpenAIUsageSnapshot {
        _ = try await fetchSession()

        var snapshots: [OpenAIUsageSnapshot] = []
        var lastError: Error?

        for candidate in usageEndpoints() {
            do {
                let request = try makeRequest(
                    endpoint: candidate.endpoint,
                    method: candidate.method,
                    body: candidate.body,
                    includeAuthorization: candidate.requiresAuth
                )
                let (data, response) = try await performRequest(request)
                let json = try decodeJSON(from: data, response: response)
                let snapshot = OpenAIUsageParser.parseSnapshot(from: json)

                print("[OpenAIAPIClient] \(candidate.endpoint) -> \(snapshot.limits.count) limit candidates")
                snapshots.append(snapshot)
            } catch {
                print("[OpenAIAPIClient] Failed \(candidate.endpoint): \(error)")
                lastError = error
            }
        }

        let merged = mergeSnapshots(snapshots)
        if !merged.limits.isEmpty || merged.planLabel != nil {
            return merged
        }

        if let lastError {
            throw lastError
        }
        throw APIError.usageDataUnavailable
    }

    private func usageEndpoints() -> [(endpoint: String, method: String, body: Data?, requiresAuth: Bool)] {
        let sentinelBody = try? JSONSerialization.data(withJSONObject: [
            "conversation_mode_kind": "primary_assistant",
            "model": "auto",
            "messages": []
        ])

        return [
            ("/backend-api/wham/usage", "GET", nil, true),
            ("/backend-api/wham/usage/credit-usage-events", "GET", nil, true),
            ("/backend-api/checkout_pricing_config/configs/\(Locale.current.regionCode ?? "US")", "GET", nil, true),
            ("/backend-api/checkout_pricing_config/configs/ES", "GET", nil, true),
            ("/backend-api/sentinel/chat-requirements", "POST", sentinelBody, true),
            ("/backend-api/accounts/check/v4-2023-04-27", "GET", nil, true),
            ("/backend-api/accounts/check", "GET", nil, true)
        ]
    }

    private func mergeSnapshots(_ snapshots: [OpenAIUsageSnapshot]) -> OpenAIUsageSnapshot {
        let planLabel = snapshots.compactMap(\.planLabel).first
        var seen = Set<OpenAIUsageLimit>()
        var mergedLimits: [OpenAIUsageLimit] = []

        for snapshot in snapshots {
            for limit in snapshot.limits where seen.insert(limit).inserted {
                mergedLimits.append(limit)
            }
        }

        return OpenAIUsageSnapshot(planLabel: planLabel, limits: mergedLimits)
    }

    private func makeRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthorization: Bool = false
    ) throws -> URLRequest {
        guard let sessionCookies else {
            throw APIError.noSessionCookies
        }

        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(sessionCookies, forHTTPHeaderField: "Cookie")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if includeAuthorization, let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        print("[OpenAIAPIClient] Request \(method) \(endpoint)")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            print("[OpenAIAPIClient] Response status: \(httpResponse.statusCode)")
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            print("[OpenAIAPIClient] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        switch response.statusCode {
        case 200 ... 299:
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(type, from: data)
            } catch {
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

    private func decodeJSON(from data: Data, response: HTTPURLResponse) throws -> Any {
        switch response.statusCode {
        case 200 ... 299:
            do {
                return try JSONSerialization.jsonObject(with: data)
            } catch {
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

struct OpenAISessionResponse: Codable, Sendable {
    let accessToken: String?
    let user: User?

    struct User: Codable, Sendable {
        let email: String?
        let name: String?
    }
}

struct OpenAIUsageSnapshot: Sendable {
    let planLabel: String?
    let limits: [OpenAIUsageLimit]
}

struct OpenAIUsageLimit: Sendable, Hashable {
    let name: String
    let utilization: Double
    let resetsAt: Date?
}

private enum OpenAIUsageParser {
    static func parseSnapshot(from json: Any) -> OpenAIUsageSnapshot {
        var collector = Collector()
        collector.walk(json, path: [])
        return OpenAIUsageSnapshot(
            planLabel: collector.planLabel,
            limits: collector.normalizedLimits()
        )
    }

    private struct Collector {
        var planLabel: String?
        private var limits: [CandidateLimit] = []

        mutating func walk(_ value: Any, path: [String]) {
            if let dict = value as? [String: Any] {
                inspect(dictionary: dict, path: path)
                for (key, nested) in dict {
                    walk(nested, path: path + [key])
                }
                return
            }

            if let array = value as? [Any] {
                for (index, nested) in array.enumerated() {
                    walk(nested, path: path + ["[\(index)]"])
                }
            }
        }

        mutating func inspect(dictionary: [String: Any], path: [String]) {
            if planLabel == nil {
                planLabel = detectPlan(in: dictionary)
            }

            if let candidate = candidateLimit(from: dictionary, path: path) {
                limits.append(candidate)
            }
        }

        private func detectPlan(in dictionary: [String: Any]) -> String? {
            let stringValues = dictionary.compactMap { key, value -> String? in
                guard let string = value as? String else { return nil }
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("plan") || normalizedKey.contains("tier") || normalizedKey.contains("subscription") {
                    return string
                }
                return nil
            }

            let knownPlans = ["free", "plus", "pro", "team", "enterprise", "business"]
            for value in stringValues {
                let lowercased = value.lowercased()
                if knownPlans.contains(where: { lowercased.contains($0) }) {
                    return value
                }
            }
            return nil
        }

        private func candidateLimit(from dictionary: [String: Any], path: [String]) -> CandidateLimit? {
            let percentKeys = ["utilization", "percent_used", "used_percent", "usage_percent", "usagePct"]
            var utilization = percentKeys.compactMap { OpenAIUsageParser.number(from: dictionary[$0]) }.first

            if utilization == nil {
                let numericTriples: [(used: [String], remaining: [String], limit: [String])] = [
                    (["used", "consumed"], ["remaining"], ["limit", "max", "quota", "total"]),
                    (["current"], ["remaining"], ["max"])
                ]

                for triple in numericTriples {
                    let usedValue = firstNumber(in: dictionary, keys: triple.used)
                    let remainingValue = firstNumber(in: dictionary, keys: triple.remaining)
                    let limitValue = firstNumber(in: dictionary, keys: triple.limit)

                    if let usedValue, let limitValue, limitValue > 0 {
                        utilization = (usedValue / limitValue) * 100
                        break
                    }

                    if let remainingValue, let limitValue, limitValue > 0 {
                        utilization = ((limitValue - remainingValue) / limitValue) * 100
                        break
                    }
                }
            }

            guard let rawUtilization = utilization else { return nil }
            let clampedUtilization = max(0, min(100, rawUtilization))

            let resetDate = extractResetDate(from: dictionary)
            let name = extractName(from: dictionary, path: path)

            return CandidateLimit(name: name, utilization: clampedUtilization, resetsAt: resetDate)
        }

        private func firstNumber(in dictionary: [String: Any], keys: [String]) -> Double? {
            for key in keys {
                if let value = OpenAIUsageParser.number(from: dictionary[key]) {
                    return value
                }
            }
            return nil
        }

        private func extractName(from dictionary: [String: Any], path: [String]) -> String {
            let preferredKeys = ["label", "name", "title", "slug", "model", "model_slug", "plan"]
            for key in preferredKeys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }

            let meaningful = path.reversed().first { segment in
                !segment.hasPrefix("[")
            }
            return meaningful ?? "usage"
        }

        private func extractResetDate(from dictionary: [String: Any]) -> Date? {
            for (key, value) in dictionary {
                let lowercased = key.lowercased()
                guard lowercased.contains("reset") || lowercased.contains("expires") || lowercased.contains("window") else {
                    continue
                }

                if let date = OpenAIUsageParser.parseDate(value) {
                    return date
                }
            }
            return nil
        }

        func normalizedLimits() -> [OpenAIUsageLimit] {
            var seen = Set<String>()
            var normalized: [OpenAIUsageLimit] = []

            for limit in limits {
                let bucketedUtilization = Int(limit.utilization.rounded())
                let resetBucket = limit.resetsAt.map { Int($0.timeIntervalSince1970 / 60) } ?? -1
                let key = "\(limit.name.lowercased())|\(bucketedUtilization)|\(resetBucket)"
                guard seen.insert(key).inserted else { continue }

                normalized.append(
                    OpenAIUsageLimit(
                        name: limit.name,
                        utilization: limit.utilization,
                        resetsAt: limit.resetsAt
                    )
                )
            }

            return normalized.sorted { lhs, rhs in
                switch (lhs.resetsAt, rhs.resetsAt) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.name < rhs.name
                }
            }
        }

        private struct CandidateLimit {
            let name: String
            let utilization: Double
            let resetsAt: Date?
        }
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let number = number(from: value) {
            if number > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }

        guard let string = value as? String, !string.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

struct OpenAIMeProfile: Sendable {
    let email: String?
    let planLabel: String?
    let displayName: String?
}

private enum OpenAIMeParser {
    static func parseProfile(from json: Any) -> OpenAIMeProfile {
        let email = findString(in: json, matching: ["email"])
        let displayName = findString(in: json, matching: ["name", "display_name"])
        let plan = findString(in: json, matching: ["plan", "plan_type", "tier", "subscription_plan"])

        return OpenAIMeProfile(email: email, planLabel: plan, displayName: displayName)
    }

    private static func findString(in value: Any, matching keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict {
                let normalized = key.lowercased()
                if keys.contains(normalized), let string = nested as? String, !string.isEmpty {
                    return string
                }
            }

            for nested in dict.values {
                if let result = findString(in: nested, matching: keys) {
                    return result
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let result = findString(in: nested, matching: keys) {
                    return result
                }
            }
        }

        return nil
    }
}
