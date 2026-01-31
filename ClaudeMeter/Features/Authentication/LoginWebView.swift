//
//  LoginWebView.swift
//  ClaudeMeter
//

import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let onSessionKeyExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Observe URL changes for SPA navigation
        context.coordinator.observeURL(webView: webView)

        let request = URLRequest(url: URL(string: "https://claude.ai/login")!)
        webView.load(request)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKeyExtracted: onSessionKeyExtracted)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionKeyExtracted: (String) -> Void
        private var hasExtractedSession = false
        private var urlObservation: NSKeyValueObservation?
        private var checkTimer: Timer?

        init(onSessionKeyExtracted: @escaping (String) -> Void) {
            self.onSessionKeyExtracted = onSessionKeyExtracted
        }

        deinit {
            urlObservation?.invalidate()
            checkTimer?.invalidate()
        }

        func observeURL(webView: WKWebView) {
            // Reset state for new login attempt
            hasExtractedSession = false
            urlObservation?.invalidate()
            checkTimer?.invalidate()

            // KVO observation for URL changes
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, change in
                guard let self, !self.hasExtractedSession else { return }
                if let url = change.newValue as? URL {
                    print("[LoginWebView] URL changed to: \(url.absoluteString)")
                    self.checkIfAuthenticated(webView: webView, url: url)
                }
            }

            // Also poll periodically for SPA changes that don't trigger KVO
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView, !self.hasExtractedSession else { return }
                if let url = webView.url {
                    self.checkIfAuthenticated(webView: webView, url: url)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasExtractedSession else { return }
            guard let url = webView.url else { return }
            print("[LoginWebView] didFinish: \(url.absoluteString)")
            checkIfAuthenticated(webView: webView, url: url)
        }

        private func checkIfAuthenticated(webView: WKWebView, url: URL) {
            guard !hasExtractedSession else { return }

            let urlString = url.absoluteString

            // Check if we're on a page that indicates successful login
            let isLoginPage = urlString.contains("/login") ||
                              urlString.contains("/oauth") ||
                              urlString.contains("/auth") ||
                              urlString.contains("accounts.google.com") ||
                              urlString.contains("isolated-segment")

            if !isLoginPage && urlString.contains("claude.ai") {
                print("[LoginWebView] Detected authenticated page: \(urlString)")
                extractAndSendCookies(webView: webView)
            }
        }

        private let allowedDomains = [
            "claude.ai"
        ]

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let host = url.host?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            let isAllowed = allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            if isAllowed {
                print("[LoginWebView] Allowing navigation to: \(url.absoluteString)")
                decisionHandler(.allow)
            } else {
                print("[LoginWebView] Blocked navigation to: \(url.absoluteString)")
                decisionHandler(.cancel)
            }
        }

        private func extractAndSendCookies(webView: WKWebView) {
            guard !hasExtractedSession else { return }

            checkTimer?.invalidate()

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtractedSession else { return }

                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                print("[LoginWebView] Found \(claudeCookies.count) claude.ai cookies:")
                for cookie in claudeCookies {
                    print("  - \(cookie.name)")
                }

                guard !claudeCookies.isEmpty else {
                    print("[LoginWebView] No cookies found!")
                    return
                }

                // Build cookie string
                let cookieString = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                print("[LoginWebView] Sending cookie string (\(cookieString.count) chars)")

                self.hasExtractedSession = true
                DispatchQueue.main.async {
                    self.onSessionKeyExtracted(cookieString)
                }
            }
        }
    }
}
