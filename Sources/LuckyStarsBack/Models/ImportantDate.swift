//
//  ImportantDate.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class ImportantDate: Model, @unchecked Sendable {
    static let schema = "important_date"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "label")
    var label: String

    @Field(key: "date")
    var date: Date

    @Field(key: "repeat_yearly")
    var repeatYearly: Bool

    @Field(key: "reminder_enabled")
    var reminderEnabled: Bool

    @OptionalField(key: "reminder_days_before")
    var reminderDaysBefore: Int?

    init() {}

    init(id: UUID? = nil, userId: UUID, label: String, date: Date) {
        self.id = id ?? UUID()
        self.userId = userId
        self.label = label
        self.date = date
        self.repeatYearly = false
        self.reminderEnabled = false
        self.reminderDaysBefore = nil
    }
}
