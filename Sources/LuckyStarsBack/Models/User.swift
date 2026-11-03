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

    @Field(key: "password")
    var password: String

    @OptionalField(key: "profile_picture")
    var profilePicture: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, firstName: String, birthDate: Date, email: String, password: String, profilePicture: String? = nil) {
        self.id = id ?? UUID()
        self.firstName = firstName
        self.birthDate = birthDate
        self.email = email
        self.password = password
        self.profilePicture = profilePicture
    }
}

