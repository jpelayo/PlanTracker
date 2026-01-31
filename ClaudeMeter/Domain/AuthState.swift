//
//  AuthState.swift
//  ClaudeMeter
//

import Foundation

enum AuthState: Sendable, Equatable {
    case unknown
    case unauthenticated
    case authenticating
    case authenticated(email: String)

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    var email: String? {
        if case .authenticated(let email) = self {
            return email
        }
        return nil
    }
}
