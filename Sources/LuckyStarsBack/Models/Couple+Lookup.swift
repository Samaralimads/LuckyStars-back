//
//  Couple+Lookup.swift
//  LuckyStarsBack
//

import Fluent
import Vapor

extension Couple {
    /// The couple a user belongs to (as either partner), if any.
    /// One indexed query, instead of loading every couple and searching in memory.
    static func forUser(_ userId: UUID, on db: any Database) async throws -> Couple? {
        try await Couple.query(on: db)
            .group(.or) {
                $0.filter(\.$partner1Id == userId)
                $0.filter(\.$partner2Id == userId)
            }
            .first()
    }
}
