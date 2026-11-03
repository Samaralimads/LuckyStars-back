//
//  ImportantDateDTO.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor

// MARK: - Create / Update Request
// repeatYearly / reminderEnabled / reminderDaysBefore are optional so older app builds keep working:
// when a field is omitted on update, the stored value is left unchanged.
struct ImportantDateRequest: Content {
    let label: String
    let date: String
    let repeatYearly: Bool?
    let reminderEnabled: Bool?
    let reminderDaysBefore: Int?
}

// MARK: - Response
struct ImportantDateResponse: Content {
    let id: UUID
    let label: String
    let date: String
    let repeatYearly: Bool
    let reminderEnabled: Bool
    let reminderDaysBefore: Int?

    init(from importantDate: ImportantDate) throws {
        self.id = try importantDate.requireID()
        self.label = importantDate.label
        self.repeatYearly = importantDate.repeatYearly
        self.reminderEnabled = importantDate.reminderEnabled
        self.reminderDaysBefore = importantDate.reminderDaysBefore

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.date = formatter.string(from: importantDate.date)
    }
}
