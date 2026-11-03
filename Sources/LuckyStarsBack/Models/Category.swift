//
//  Category.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class Category: Model, @unchecked Sendable {
    static let schema = "category"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    init() {}
}
