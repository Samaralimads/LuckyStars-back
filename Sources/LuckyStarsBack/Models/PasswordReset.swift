//
//  PasswordReset.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Fluent
import Vapor

final class PasswordReset: Model, @unchecked Sendable {
    static let schema = "password_reset"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "code")
    var code: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "used")
    var used: Bool

    /// Wrong guesses so far. The code is locked after too many (see PasswordResetController).
    @Field(key: "attempts")
    var attempts: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userId: UUID, code: String, expiresAt: Date) {
        self.id = id ?? UUID()
        self.userId = userId
        self.code = code
        self.expiresAt = expiresAt
        self.used = false
        self.attempts = 0
    }
}
