//
//  SettingsView.swift
//  PlanTracker
//

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: UsageViewModel

    var body: some View {
        Form {
            Section(String(localized: "General")) {
                Toggle(String(localized: "Launch at login"), isOn: $viewModel.launchAtLogin)

                Picker(String(localized: "Language"), selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(String(localized: "Display")) {
                Picker(String(localized: "Show percentage"), selection: $viewModel.showRemainingPercent) {
                    Text(String(localized: "Remaining")).tag(true)
                    Text(String(localized: "Used")).tag(false)
                }
                .pickerStyle(.menu)

                Picker(String(localized: "Update interval"), selection: $viewModel.pollingIntervalMinutes) {
                    Text(String(localized: "3 minutes")).tag(3)
                    Text(String(localized: "5 minutes")).tag(5)
                    Text(String(localized: "10 minutes")).tag(10)
                    Text(String(localized: "15 minutes")).tag(15)
                    Text(String(localized: "30 minutes")).tag(30)
                    Text(String(localized: "60 minutes")).tag(60)
                }
                .pickerStyle(.menu)
            }

            Section(String(localized: "Account")) {
                if let email = viewModel.authState.email {
                    LabeledContent(String(localized: "Signed in as"), value: email)

                    LabeledContent(String(localized: "Plan"), value: viewModel.usageData.planTier.displayName)

                    Button(String(localized: "Sign Out"), role: .destructive) {
                        Task {
                            await viewModel.logout()
                        }
                    }
                } else {
                    Text(String(localized: "Not signed in"))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent(String(localized: "Version"), value: Bundle.main.appVersion)
                LabeledContent(String(localized: "Developer")) {
                    Link("infinitecontext.com", destination: URL(string: "https://infinitecontext.com")!)
                }
                LabeledContent(String(localized: "About")) {
                    Text(String(localized: "This is not an official app.\nIt is not endorsed by, nor affiliated with Anthropic (PBC) or Claude™."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build)) Beta"
    }
}
