//
//  PlannedActivityController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor
import Fluent
import SQLKit

struct PlannedActivityController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let planned = routes.grouped("planned-activities").grouped(JWTMiddleware())

        planned.post(use: propose)
        planned.get("couple", use: getCoupleActivities)
        planned.put(":plannedId", "accept", use: accept)
        planned.put(":plannedId", "decline", use: decline)
        planned.put(":plannedId", "reschedule", use: reschedule)
    }

    // MARK: - POST /planned-activities
    @Sendable
    func propose(req: Request) async throws -> PlannedActivityResponse {
        let userId = try currentUserId(req)
        let body = try req.content.decode(ProposeActivityRequest.self)

        let proposedDate = try parseProposedDate(body.proposedDate)
        try validateReminder(enabled: body.reminderEnabled, daysBefore: body.reminderDaysBefore)

        guard try await Activity.find(body.activityId, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Activity not found.")
        }

        // A proposal needs someone to answer it.
        let coupleId = try await pairedCoupleId(for: userId, db: req.db)

        let planned = PlannedActivity(
            activityId: body.activityId,
            coupleId: coupleId,
            plannedByUserId: userId,
            proposedDate: proposedDate,
            reminderEnabled: body.reminderEnabled,
            reminderDaysBefore: body.reminderDaysBefore
        )

        try await planned.save(on: req.db)
        return try await buildResponse(for: planned, db: req.db)
    }

    // MARK: - GET /planned-activities/couple
    @Sendable
    func getCoupleActivities(req: Request) async throws -> [PlannedActivityResponse] {
        let userId = try currentUserId(req)

        // Also works for a user whose partner left: they still see the couple's dates.
        guard let couple = try await Couple.forUser(userId, on: req.db) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }
        let coupleId = try couple.requireID()

        let activities = try await PlannedActivity.query(on: req.db)
            .filter(\.$coupleId == coupleId)
            .sort(\.$proposedDate, .descending)
            .all()

        return try await activities.asyncMap { try await buildResponse(for: $0, db: req.db) }
    }

    // MARK: - PUT /planned-activities/:id/accept
    @Sendable
    func accept(req: Request) async throws -> PlannedActivityResponse {
        try await req.db.transaction { db in
            let planned = try await getAndValidate(req: req, db: db)
            planned.bookingStatus = "accepted"
            planned.responseDate = Date()
            try await planned.save(on: db)
            return try await buildResponse(for: planned, db: db)
        }
    }

    // MARK: - PUT /planned-activities/:id/decline
    @Sendable
    func decline(req: Request) async throws -> PlannedActivityResponse {
        // The note is optional, but a body that is there and broken is an error, not "no note".
        let note: String? = req.body.data == nil
            ? nil
            : try req.content.decode(DeclineActivityRequest.self).note
        try validateNote(note)

        return try await req.db.transaction { db in
            let planned = try await getAndValidate(req: req, db: db)
            planned.bookingStatus = "rejected"
            planned.responseDate = Date()
            planned.note = note
            try await planned.save(on: db)
            return try await buildResponse(for: planned, db: db)
        }
    }

    // MARK: - PUT /planned-activities/:id/reschedule
    @Sendable
    func reschedule(req: Request) async throws -> PlannedActivityResponse {
        let userId = try currentUserId(req)
        let body = try req.content.decode(RescheduleActivityRequest.self)

        let newDate = try parseProposedDate(body.proposedDate)
        try validateReminder(enabled: body.reminderEnabled, daysBefore: body.reminderDaysBefore)
        try validateNote(body.note)

        // Both steps or neither: otherwise a failure in between leaves the old proposal
        // rejected and no new one.
        return try await req.db.transaction { db in
            let planned = try await getAndValidate(req: req, db: db)

            planned.bookingStatus = "rejected"
            planned.responseDate = Date()
            planned.note = body.note
            try await planned.save(on: db)

            let newProposal = PlannedActivity(
                activityId: planned.activityId,
                coupleId: planned.coupleId,
                plannedByUserId: userId,
                proposedDate: newDate,
                reminderEnabled: body.reminderEnabled,
                reminderDaysBefore: body.reminderDaysBefore,
                note: body.note
            )

            try await newProposal.save(on: db)
            return try await buildResponse(for: newProposal, db: db)
        }
    }

    // MARK: - Helpers
    private func currentUserId(_ req: Request) throws -> UUID {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }
        return userId
    }

    /// Loads the proposal (locked until the transaction ends, so two answers can't both succeed)
    /// and checks that the caller may answer it.
    private func getAndValidate(req: Request, db: any Database) async throws -> PlannedActivity {
        let userId = try currentUserId(req)

        guard
            let idString = req.parameters.get("plannedId"),
            let uuid = UUID(uuidString: idString)
        else {
            throw Abort(.notFound, reason: "Planned activity not found.")
        }

        try await lockRow(uuid, db: db)

        guard let planned = try await PlannedActivity.find(uuid, on: db) else {
            throw Abort(.notFound, reason: "Planned activity not found.")
        }

        guard let couple = try await Couple.forUser(userId, on: db),
              planned.coupleId == (try couple.requireID())
        else {
            throw Abort(.forbidden, reason: "You are not part of this couple.")
        }

        guard planned.plannedByUserId != userId else {
            throw Abort(.forbidden, reason: "You can't respond to your own proposal.")
        }

        guard planned.bookingStatus == "pending" else {
            throw Abort(.conflict, reason: "This proposal has already been responded to.")
        }

        return planned
    }

    private func lockRow(_ id: UUID, db: any Database) async throws {
        guard let sql = db as? any SQLDatabase else { return }
        try await sql.raw("""
            SELECT id FROM planned_activity
            WHERE id = UNHEX(REPLACE(\(bind: id.uuidString), '-', ''))
            FOR UPDATE
        """).run()
    }

    /// The caller's couple, which must already have both partners.
    private func pairedCoupleId(for userId: UUID, db: any Database) async throws -> UUID {
        guard let couple = try await Couple.forUser(userId, on: db) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }
        guard couple.partner2Id != nil else {
            throw Abort(.conflict, reason: "Pair with your partner first, then you can plan dates together.")
        }
        return try couple.requireID()
    }

    private func parseProposedDate(_ string: String) throws -> Date {
        guard let date = dateFormatter().date(from: string) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD HH:mm.")
        }
        guard date > Date().addingTimeInterval(-5 * 60) else {
            throw Abort(.badRequest, reason: "The date must be in the future.")
        }
        return date
    }

    private func validateReminder(enabled: Bool, daysBefore: Int?) throws {
        if enabled {
            guard let daysBefore, (1...365).contains(daysBefore) else {
                throw Abort(.badRequest, reason: "reminderDaysBefore must be between 1 and 365 when the reminder is enabled.")
            }
        }
    }

    private func validateNote(_ note: String?) throws {
        if let note, note.count > 255 {
            throw Abort(.badRequest, reason: "The note is too long (255 characters at most).")
        }
    }

    private func buildResponse(for planned: PlannedActivity, db: any Database) async throws -> PlannedActivityResponse {
        let activity = try await Activity.find(planned.activityId, on: db)
        let formatter = dateFormatter()

        return PlannedActivityResponse(
            id: try planned.requireID(),
            activityId: planned.activityId,
            activityTitle: activity?.title ?? "Unknown",
            coupleId: planned.coupleId,
            plannedByUserId: planned.plannedByUserId,
            proposedDate: formatter.string(from: planned.proposedDate),
            responseDate: planned.responseDate.map { formatter.string(from: $0) },
            bookingStatus: planned.bookingStatus,
            reminderEnabled: planned.reminderEnabled,
            reminderDaysBefore: planned.reminderDaysBefore,
            note: planned.note,
            createdAt: planned.createdAt.map { formatter.string(from: $0) }
        )
    }

    private func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results = [T]()
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
