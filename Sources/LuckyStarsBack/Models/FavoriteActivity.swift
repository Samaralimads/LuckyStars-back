//
//  FavoriteActivity.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class FavoriteActivity: Model, @unchecked Sendable {
    static let schema = "favorite_activity"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "activity_id")
    var activityId: UUID

    init() {}

    init(id: UUID? = nil, userId: UUID, activityId: UUID) {
        self.id = id ?? UUID()
        self.userId = userId
        self.activityId = activityId
    }
}
