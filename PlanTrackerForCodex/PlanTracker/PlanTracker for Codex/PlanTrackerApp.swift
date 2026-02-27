//
//  PlanTrackerApp.swift
//  PlanTracker
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import SwiftUI

@main
struct PlanTrackerApp: App {
    @State private var viewModel = UsageViewModel()
    @State private var hasCheckedAuth = false

    init() {
        ensureSingleInstance()
    }

    private func ensureSingleInstance() {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if runningApps.count > 1 {
            // Terminate after a brief delay to ensure NSApp is ready
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            MenuBarIconLabel(
                usageData: viewModel.usageData,
                authState: viewModel.authState,
                showRemainingPercent: viewModel.showRemainingPercent
            )
            .task {
                guard !hasCheckedAuth else { return }
                hasCheckedAuth = true
                await viewModel.checkAuthentication()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Sign in to ChatGPT", id: "login") {
            LoginView { sessionCookies in
                await viewModel.handleLoginSuccess(sessionCookies: sessionCookies)
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
