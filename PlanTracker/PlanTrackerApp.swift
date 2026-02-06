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
            NSApp.terminate(nil)
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

        Window("Sign in to Claude", id: "login") {
            LoginView { sessionKey in
                Task {
                    await viewModel.handleLoginSuccess(sessionKey: sessionKey)
                }
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
