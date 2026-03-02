//
//  PlanTrackerApp.swift
//  PlanTracker
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import AppKit
import os
import SwiftUI

@main
struct PlanTrackerApp: App {
    @NSApplicationDelegateAdaptor(PlanTrackerAppDelegate.self) private var appDelegate
    @State private var viewModel = UsageViewModel()
    @State private var hasCheckedAuth = false

    init() {
        AppRuntimeState.recordBreadcrumb("app-init")
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

enum AppMemoryPressureLevel: String, Sendable {
    case warning
    case critical
}

extension Notification.Name {
    static let planTrackerMemoryPressure = Notification.Name("PlanTrackerMemoryPressure")
}

struct LaunchRecoveryState: Sendable {
    let wasUnexpectedTermination: Bool
    let previousLaunchDate: Date?
    let previousHeartbeatDate: Date?
}

enum AppRuntimeState {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "Lifecycle"
    )
    private static let defaults = UserDefaults.standard
    private static let didLaunchCleanlyKey = "appRuntime.didLaunchCleanly"
    private static let lastLaunchDateKey = "appRuntime.lastLaunchDate"
    private static let lastHeartbeatDateKey = "appRuntime.lastHeartbeatDate"
    private static let lastBreadcrumbsKey = "appRuntime.lastBreadcrumbs"
    private static var cachedLaunchState: LaunchRecoveryState?

    static func beginLaunchIfNeeded() -> LaunchRecoveryState {
        if let cachedLaunchState {
            return cachedLaunchState
        }

        let previousLaunchDate = defaults.object(forKey: lastLaunchDateKey) as? Date
        let previousHeartbeatDate = defaults.object(forKey: lastHeartbeatDateKey) as? Date
        let hadPriorLaunch = previousLaunchDate != nil
        let didLaunchCleanly = defaults.object(forKey: didLaunchCleanlyKey) as? Bool ?? true

        let state = LaunchRecoveryState(
            wasUnexpectedTermination: hadPriorLaunch && !didLaunchCleanly,
            previousLaunchDate: previousLaunchDate,
            previousHeartbeatDate: previousHeartbeatDate
        )

        defaults.set(false, forKey: didLaunchCleanlyKey)
        defaults.set(Date(), forKey: lastLaunchDateKey)
        defaults.set(Date(), forKey: lastHeartbeatDateKey)
        cachedLaunchState = state

        recordBreadcrumb("launch-begin")
        return state
    }

    static func recordHeartbeat(reason: String) {
        defaults.set(Date(), forKey: lastHeartbeatDateKey)
        recordBreadcrumb("heartbeat-\(reason)")
    }

    static func recordBreadcrumb(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let entry = "\(formatter.string(from: Date())) \(message)"
        logger.notice("\(entry, privacy: .public)")

        var breadcrumbs = defaults.stringArray(forKey: lastBreadcrumbsKey) ?? []
        breadcrumbs.append(entry)
        if breadcrumbs.count > 40 {
            breadcrumbs.removeFirst(breadcrumbs.count - 40)
        }
        defaults.set(breadcrumbs, forKey: lastBreadcrumbsKey)
        defaults.set(Date(), forKey: lastHeartbeatDateKey)
    }

    static func markCleanTermination() {
        defaults.set(true, forKey: didLaunchCleanlyKey)
        defaults.set(Date(), forKey: lastHeartbeatDateKey)
        recordBreadcrumb("termination-clean")
    }
}

final class PlanTrackerAppDelegate: NSObject, NSApplicationDelegate {
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-finish-launching")
        installMemoryPressureSource()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-become-active")
    }

    func applicationDidResignActive(_ notification: Notification) {
        AppRuntimeState.recordBreadcrumb("did-resign-active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntimeState.markCleanTermination()
    }

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleMemoryPressureEvent(source.data)
        }
        source.resume()
        memoryPressureSource = source
        AppRuntimeState.recordBreadcrumb("memory-pressure-monitor-installed")
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        let level: AppMemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            return
        }

        AppRuntimeState.recordBreadcrumb("memory-pressure-\(level.rawValue)")
        NotificationCenter.default.post(name: .planTrackerMemoryPressure, object: level)
    }
}
