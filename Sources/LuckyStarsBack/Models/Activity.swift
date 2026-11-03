//
//  Activity.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class Activity: Model, @unchecked Sendable {
    static let schema = "activity"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @Field(key: "budget")
    var budget: String

    @Field(key: "duration")
    var duration: Int

    @Field(key: "is_indoor")
    var isIndoor: Bool

    @Field(key: "category_id")
    var categoryId: UUID

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}
}
