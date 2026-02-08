//
//  MenuBarView.swift
//  PlanTracker
//

import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.authState.isAuthenticated {
                authenticatedContent
            } else {
                unauthenticatedContent
            }
        }
        .frame(width: 290)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "Claude Tracker"))
                    .font(.headline)
                Spacer()
                Text(viewModel.usageData.planTier.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .clipShape(.capsule)
            }

            if let email = viewModel.authState.email {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()

        Divider()

        // Usage Info
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.usageData.fiveHourUtilization == nil && viewModel.usageData.sevenDayUtilization == nil {
                // No usage data available (free tier or limits not applicable)
                Text(String(localized: "No usage limits available"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                // 5-Hour Usage
                if let utilization = viewModel.usageData.fiveHourUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "5-Hour Limit"))
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        ProgressView(value: utilization / 100)
                            .tint(colorForUtilization(utilization))
                        if let reset = viewModel.usageData.formattedFiveHourReset {
                            Text("\(String(localized: "Resets")) \(reset)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 7-Day Usage (Pro)
                if let utilization = viewModel.usageData.sevenDayUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "7-Day Limit (Pro)"))
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        ProgressView(value: utilization / 100)
                            .tint(colorForUtilization(utilization))
                        if let reset = viewModel.usageData.formattedSevenDayReset {
                            Text("\(String(localized: "Resets")) \(reset)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 7-Day Opus Usage
                if let utilization = viewModel.usageData.sevenDayOpusUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Opus (7-Day)"))
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        ProgressView(value: utilization / 100)
                            .tint(colorForUtilization(utilization))
                        if let reset = viewModel.usageData.formattedSevenDayOpusReset {
                            Text("\(String(localized: "Resets")) \(reset)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 7-Day Sonnet Usage
                if let utilization = viewModel.usageData.sevenDaySonnetUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Sonnet (7-Day)"))
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        ProgressView(value: utilization / 100)
                            .tint(colorForUtilization(utilization))
                        if let reset = viewModel.usageData.formattedSevenDaySonnetReset {
                            Text("\(String(localized: "Resets")) \(reset)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()

        if let error = viewModel.errorMessage {
            Divider()
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        Divider()

        // Actions
        VStack(spacing: 0) {
            Button {
                Task {
                    await viewModel.refreshUsage()
                }
            } label: {
                HStack {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if let lastUpdated = viewModel.lastUpdated {
                        Text(lastUpdated, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            SettingsLink {
                HStack {
                    Label(String(localized: "Settings..."), systemImage: "gear")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Button(role: .destructive) {
                Task {
                    await viewModel.logout()
                }
            } label: {
                HStack {
                    Label(String(localized: "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Label(String(localized: "Quit"), systemImage: "power")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(String(localized: "Sign in to Claude"))
                .font(.headline)

            Text(String(localized: "Track your Claude.ai usage from the menu bar"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(String(localized: "Sign In")) {
                openWindow(id: "login")
            }
            .buttonStyle(.borderedProminent)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Divider()

            SettingsLink {
                HStack {
                    Label(String(localized: "Settings..."), systemImage: "gear")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Button {
                showAbout.toggle()
            } label: {
                HStack {
                    Label(String(localized: "About"), systemImage: "info.circle")
                    Spacer()
                    Image(systemName: showAbout ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            if showAbout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Version"))
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(String(localized: "Developer"))
                        Spacer()
                        Link("infinitecontext.com", destination: URL(string: "https://infinitecontext.com")!)
                    }
                    Text(String(localized: "This is not an official app.\nIt is not endorsed by, nor affiliated with Anthropic (PBC) or Claude™."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Label(String(localized: "Quit"), systemImage: "power")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding()
    }

    private func colorForUtilization(_ utilization: Double) -> Color {
        switch utilization {
        case ..<50: .green
        case 50..<80: .yellow
        default: .red
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build)) Beta"
    }
}
