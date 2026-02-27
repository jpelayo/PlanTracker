//
//  WebViewCookieManager.swift
//  PlanTracker
//

import Foundation
import WebKit

actor WebViewCookieManager {

    /// Extracts OpenAI/ChatGPT session cookies from WKWebsiteDataStore
    func extractSessionCookies() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let openAICookies = cookies.filter { cookie in
                        cookie.domain.contains("chatgpt.com")
                        || cookie.domain.contains("openai.com")
                        || cookie.domain.contains("chat.openai.com")
                    }

                    print("[WebViewCookieManager] Found \(openAICookies.count) OpenAI cookies")
                    for cookie in openAICookies {
                        print("  - \(cookie.name)")
                    }

                    guard !openAICookies.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let hasLikelyAuthCookie = openAICookies.contains { cookie in
                        let name = cookie.name.lowercased()
                        return name.contains("session")
                            || name.contains("auth")
                            || name.contains("token")
                    }
                    guard hasLikelyAuthCookie else {
                        print("[WebViewCookieManager] No auth-like OpenAI cookies found")
                        continuation.resume(returning: nil)
                        return
                    }

                    // Build cookie string for API requests
                    let cookieString = openAICookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    continuation.resume(returning: cookieString)
                }
            }
        }
    }

    /// Clears all OpenAI-related cookies from WKWebsiteDataStore
    func clearSessionCookies() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let dataStore = WKWebsiteDataStore.default()

                // First, remove cookies
                dataStore.httpCookieStore.getAllCookies { cookies in
                    let openAICookies = cookies.filter { cookie in
                        cookie.domain.contains("chatgpt.com")
                        || cookie.domain.contains("openai.com")
                        || cookie.domain.contains("chat.openai.com")
                    }

                    let group = DispatchGroup()
                    for cookie in openAICookies {
                        group.enter()
                        dataStore.httpCookieStore.delete(cookie) {
                            group.leave()
                        }
                    }

                    group.notify(queue: .main) {
                        // Also clear website data
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                            let openAIRecords = records.filter {
                                $0.displayName.contains("chatgpt.com")
                                || $0.displayName.contains("openai.com")
                                || $0.displayName.contains("chat.openai.com")
                            }
                            dataStore.removeData(ofTypes: dataTypes, for: openAIRecords) {
                                print("[WebViewCookieManager] Cleared all OpenAI session data")
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }
}
