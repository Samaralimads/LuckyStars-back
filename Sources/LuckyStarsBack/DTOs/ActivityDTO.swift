//
//  ActivityDTO.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor

// MARK: - Category Response
struct CategoryResponse: Content {
    let id: UUID
    let name: String

    init(from category: Category) throws {
        self.id = try category.requireID()
        self.name = category.name
    }
}

// MARK: - Activity Response
struct ActivityResponse: Content {
    let id: UUID
    let title: String
    let description: String
    let budget: String
    let duration: Int
    let isIndoor: Bool
    let categoryId: UUID
    let categoryName: String

    init(from activity: Activity, categoryName: String) throws {
        self.id = try activity.requireID()
        self.title = activity.title
        self.description = activity.description
        self.budget = activity.budget
        self.duration = activity.duration
        self.isIndoor = activity.isIndoor
        self.categoryId = activity.categoryId
        self.categoryName = categoryName
    }
}
