//
//  User.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class User: Model, @unchecked Sendable {
    static let schema = "user"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "first_name")
    var firstName: String

    @Field(key: "birth_date")
    var birthDate: Date

    @Field(key: "email")
    var email: String

    /// nil for accounts created with Sign in with Apple.
    @OptionalField(key: "password")
    var password: String?

    /// Apple's stable id for this person (the `sub` of their identity token).
    @OptionalField(key: "apple_user_id")
    var appleUserId: String?

    /// Kept only to revoke the Apple link when the account is deleted.
    @OptionalField(key: "apple_refresh_token")
    var appleRefreshToken: String?

    @OptionalField(key: "profile_picture")
    var profilePicture: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, firstName: String, birthDate: Date, email: String, password: String?, appleUserId: String? = nil, profilePicture: String? = nil) {
        self.id = id ?? UUID()
        self.firstName = firstName
        self.birthDate = birthDate
        self.email = email
        self.password = password
        self.appleUserId = appleUserId
        self.profilePicture = profilePicture
    }
}

