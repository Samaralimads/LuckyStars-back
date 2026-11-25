//
//  DeviceToken.swift
//  LuckyStarsBack
//
//  The push address of one phone (given by Apple), and whose phone it is.
//

import Fluent
import Vapor

final class DeviceToken: Model, @unchecked Sendable {
    static let schema = "device_token"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "token")
    var token: String

    /// "sandbox" for builds run from Xcode, "production" for TestFlight and the App Store.
    @Field(key: "environment")
    var environment: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userId: UUID, token: String, environment: String) {
        self.id = id ?? UUID()
        self.userId = userId
        self.token = token
        self.environment = environment
    }
}
