//
//  Couple.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class Couple: Model, @unchecked Sendable {
    static let schema = "couple"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "partner1_id")
    var partner1Id: UUID

    @OptionalField(key: "partner2_id")
    var partner2Id: UUID?

    @Field(key: "relationship_start_date")
    var relationshipStartDate: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, partner1Id: UUID, partner2Id: UUID? = nil, relationshipStartDate: Date) {
        self.id = id ?? UUID()
        self.partner1Id = partner1Id
        self.partner2Id = partner2Id
        self.relationshipStartDate = relationshipStartDate
    }
}
