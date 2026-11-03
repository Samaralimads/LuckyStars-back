//
//  PlannedActivityController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor
import Fluent

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
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let body = try req.content.decode(ProposeActivityRequest.self)

        let formatter = dateFormatter()
        guard let proposedDate = formatter.date(from: body.proposedDate) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD HH:mm.")
        }

        if body.reminderEnabled && (body.reminderDaysBefore == nil || body.reminderDaysBefore! <= 0) {
            throw Abort(.badRequest, reason: "reminder_days_before must be greater than 0 when reminder is enabled.")
        }

        let coupleId = try await getCoupleId(for: userId, db: req.db)

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
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let coupleId = try await getCoupleId(for: userId, db: req.db)

        let activities = try await PlannedActivity.query(on: req.db)
            .filter(\.$coupleId == coupleId)
            .sort(\.$proposedDate, .descending)
            .all()

        return try await activities.asyncMap { try await buildResponse(for: $0, db: req.db) }
    }

    // MARK: - PUT /planned-activities/:id/accept
    @Sendable
    func accept(req: Request) async throws -> PlannedActivityResponse {
        let planned = try await getAndValidate(req: req)
        planned.bookingStatus = "accepted"
        planned.responseDate = Date()
        try await planned.save(on: req.db)
        return try await buildResponse(for: planned, db: req.db)
    }

    // MARK: - PUT /planned-activities/:id/decline
    @Sendable
    func decline(req: Request) async throws -> PlannedActivityResponse {
        let planned = try await getAndValidate(req: req)
        let body = try? req.content.decode(DeclineActivityRequest.self)
        planned.bookingStatus = "rejected"
        planned.responseDate = Date()
        planned.note = body?.note
        try await planned.save(on: req.db)
        return try await buildResponse(for: planned, db: req.db)
    }

    // MARK: - PUT /planned-activities/:id/reschedule
    @Sendable
    func reschedule(req: Request) async throws -> PlannedActivityResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let planned = try await getAndValidate(req: req)
        let body = try req.content.decode(RescheduleActivityRequest.self)

        let formatter = dateFormatter()
        guard let newDate = formatter.date(from: body.proposedDate) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD HH:mm.")
        }

        planned.bookingStatus = "rejected"
        planned.responseDate = Date()
        planned.note = body.note
        try await planned.save(on: req.db)

        let coupleId = try await getCoupleId(for: userId, db: req.db)
        let newProposal = PlannedActivity(
            activityId: planned.activityId,
            coupleId: coupleId,
            plannedByUserId: userId,
            proposedDate: newDate,
            reminderEnabled: body.reminderEnabled,
            reminderDaysBefore: body.reminderDaysBefore,
            note: body.note
        )

        try await newProposal.save(on: req.db)
        return try await buildResponse(for: newProposal, db: req.db)
    }

    // MARK: - Helpers
    private func getAndValidate(req: Request) async throws -> PlannedActivity {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        guard
            let idString = req.parameters.get("plannedId"),
            let uuid = UUID(uuidString: idString),
            let planned = try await PlannedActivity.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "Planned activity not found.")
        }

        let coupleId = try await getCoupleId(for: userId, db: req.db)
        guard planned.coupleId == coupleId else {
            throw Abort(.forbidden, reason: "You are not part of this couple.")
        }

        guard planned.bookingStatus == "pending" else {
            throw Abort(.conflict, reason: "This proposal has already been responded to.")
        }

        return planned
    }

    private func getCoupleId(for userId: UUID, db: any Database) async throws -> UUID {
        let couples = try await Couple.query(on: db).all()
        guard let couple = couples.first(where: {
            $0.partner1Id == userId || $0.partner2Id == userId
        }) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }
        return try couple.requireID()
    }

    private func buildResponse(for planned: PlannedActivity, db: any Database) async throws -> PlannedActivityResponse {
        let activity = try await Activity.find(planned.activityId, on: db)
        let formatter = dateFormatter()
        let createdFormatter = DateFormatter()
        createdFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        createdFormatter.timeZone = TimeZone(identifier: "UTC")

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
            createdAt: planned.createdAt.map { createdFormatter.string(from: $0) }
        )
    }

    private func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
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
