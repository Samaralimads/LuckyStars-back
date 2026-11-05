//
//  Validation.swift
//  LuckyStarsBack
//
//  Input rules shared by the controllers.
//

import Vapor

enum Validation {
    /// Same rules as the app: at least 8 characters, one uppercase letter, one digit.
    /// At most 72 bytes, because bcrypt ignores everything after that.
    static func checkPassword(_ password: String) throws {
        guard password.count >= 8,
              password.contains(where: \.isUppercase),
              password.contains(where: \.isNumber)
        else {
            throw Abort(.badRequest, reason: "Password must have at least 8 characters, one uppercase letter and one number.")
        }
        guard password.utf8.count <= 72 else {
            throw Abort(.badRequest, reason: "Password is too long.")
        }
    }

    static func checkEmail(_ email: String) throws {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 255,
              parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !email.contains(" ")
        else {
            throw Abort(.badRequest, reason: "Please enter a valid email address.")
        }
    }

    static func checkName(_ name: String) throws {
        guard (1...50).contains(name.count) else {
            throw Abort(.badRequest, reason: "Name must be between 1 and 50 characters.")
        }
    }
}

extension String {
    /// Emails are compared trimmed and lowercased, so "Sam@x.com " and "sam@x.com" are one account.
    var normalizedEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escapes text before it goes into an HTML email.
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Date-only values ("yyyy-MM-dd") exchanged with the app.
enum DayFormat {
    static func make() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}
