//
//  LoginView.swift
//  ClaudeMeter
//

import SwiftUI

struct LoginView: View {
    let onSessionKeyExtracted: (String) -> Void
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var webViewID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Claude"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismissWindow(id: "login")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            LoginWebView(onSessionKeyExtracted: { sessionKey in
                onSessionKeyExtracted(sessionKey)
                dismissWindow(id: "login")
            })
            .id(webViewID)
        }
        .frame(width: 480, height: 640)
        .onAppear {
            webViewID = UUID()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
