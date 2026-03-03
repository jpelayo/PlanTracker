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
    private static let lastLaunchTimestampKey = "appRuntime.lastLaunchTimestamp"
    private static let lastHeartbeatDateKey = "appRuntime.lastHeartbeatDate"
    private static let lastHeartbeatTimestampKey = "appRuntime.lastHeartbeatTimestamp"
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

        let now = Date()
        defaults.set(false, forKey: didLaunchCleanlyKey)
        defaults.set(now, forKey: lastLaunchDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastLaunchTimestampKey)
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markMainAppLaunch(at: now)
        synchronize()
        cachedLaunchState = state

        recordBreadcrumb("launch-begin")
        return state
    }

    static func recordHeartbeat(reason: String) {
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markHeartbeat(at: now)
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
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markHeartbeat(at: now)
        synchronize()
    }

    static func markCleanTermination() {
        guard isPrimaryInstance else { return }
        defaults.set(true, forKey: didLaunchCleanlyKey)
        let now = Date()
        defaults.set(now, forKey: lastHeartbeatDateKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
        LoginItemSharedState.markCleanTermination(at: now)
        recordBreadcrumb("termination-clean")
        synchronize()
    }

    static func prepareForUserInitiatedTermination(reason: String) {
        guard isPrimaryInstance else { return }
        let now = Date()
        defaults.set(true, forKey: didLaunchCleanlyKey)
        LoginItemSharedState.markUserInitiatedTermination(at: now)
        recordBreadcrumb("termination-user-\(reason)")
        synchronize()
    }

    private static var isPrimaryInstance: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count <= 1
    }

    private static func synchronize() {
        defaults.synchronize()
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
