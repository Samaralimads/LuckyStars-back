//
//  PlannedActivity.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class PlannedActivity: Model, @unchecked Sendable {
    static let schema = "planned_activity"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "activity_id")
    var activityId: UUID

    @OptionalField(key: "couple_id")
    var coupleId: UUID?

    @Field(key: "planned_by_user_id")
    var plannedByUserId: UUID

    @Field(key: "proposed_date")
    var proposedDate: Date

    @OptionalField(key: "response_date")
    var responseDate: Date?

    @Field(key: "booking_status")
    var bookingStatus: String

    @Field(key: "reminder_enabled")
    var reminderEnabled: Bool

    @OptionalField(key: "reminder_days_before")
    var reminderDaysBefore: Int?

    @OptionalField(key: "note")
    var note: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        activityId: UUID,
        coupleId: UUID?,
        plannedByUserId: UUID,
        proposedDate: Date,
        bookingStatus: String = "pending",
        reminderEnabled: Bool = false,
        reminderDaysBefore: Int? = nil,
        note: String? = nil
    ) {
        self.id = id ?? UUID()
        self.activityId = activityId
        self.coupleId = coupleId
        self.plannedByUserId = plannedByUserId
        self.proposedDate = proposedDate
        self.bookingStatus = bookingStatus
        self.reminderEnabled = reminderEnabled
        self.reminderDaysBefore = reminderDaysBefore
        self.note = note
    }
}
