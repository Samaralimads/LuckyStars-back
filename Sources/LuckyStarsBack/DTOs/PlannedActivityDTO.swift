//
//  PlannedActivityDTO.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor

// MARK: - Propose Request
struct ProposeActivityRequest: Content {
    let activityId: UUID
    let proposedDate: String
    let reminderEnabled: Bool
    let reminderDaysBefore: Int?
}

// MARK: - Decline Request
struct DeclineActivityRequest: Content {
    let note: String?
}

// MARK: - Reschedule Request
struct RescheduleActivityRequest: Content {
    let proposedDate: String        
    let note: String?
    let reminderEnabled: Bool
    let reminderDaysBefore: Int?
}

// MARK: - Planned Activity Response
struct PlannedActivityResponse: Content {
    let id: UUID
    let activityId: UUID
    let activityTitle: String
    let coupleId: UUID?
    let plannedByUserId: UUID
    let proposedDate: String
    let responseDate: String?
    let bookingStatus: String
    let reminderEnabled: Bool
    let reminderDaysBefore: Int?
    let note: String?
    let createdAt: String?
}
