//
//  ImportantDateController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor
import Fluent

struct ImportantDateController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let dates = routes.grouped("important-dates").grouped(JWTMiddleware())

        dates.get(use: list)
        dates.post(use: create)
        dates.put(":dateId", use: update)
        dates.delete(":dateId", use: delete)
    }

    // MARK: - GET /important-dates
    @Sendable
    func list(req: Request) async throws -> [ImportantDateResponse] {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let dates = try await ImportantDate.query(on: req.db)
            .filter(\.$userId == userId)
            .sort(\.$date, .ascending)
            .all()

        return try dates.map { try ImportantDateResponse(from: $0) }
    }

    // MARK: - POST /important-dates
    @Sendable
    func create(req: Request) async throws -> ImportantDateResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let body = try req.content.decode(ImportantDateRequest.self)
        let date = try parseDate(body.date)

        let importantDate = ImportantDate(userId: userId, label: body.label, date: date)
        apply(body, to: importantDate)
        try await importantDate.save(on: req.db)

        return try ImportantDateResponse(from: importantDate)
    }

    // MARK: - PUT /important-dates/:id
    @Sendable
    func update(req: Request) async throws -> ImportantDateResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let importantDate = try await getAndValidate(req: req, userId: userId)
        let body = try req.content.decode(ImportantDateRequest.self)

        importantDate.label = body.label
        importantDate.date = try parseDate(body.date)
        apply(body, to: importantDate)
        try await importantDate.save(on: req.db)

        return try ImportantDateResponse(from: importantDate)
    }

    // MARK: - DELETE /important-dates/:id
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let importantDate = try await getAndValidate(req: req, userId: userId)
        try await importantDate.delete(on: req.db)

        return .noContent
    }

    // MARK: - Helpers
    private func getAndValidate(req: Request, userId: UUID) async throws -> ImportantDate {
        guard
            let idString = req.parameters.get("dateId"),
            let uuid = UUID(uuidString: idString),
            let importantDate = try await ImportantDate.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "Important date not found.")
        }

        guard importantDate.userId == userId else {
            throw Abort(.forbidden, reason: "You do not have permission to modify this date.")
        }

        return importantDate
    }

    /// Copies the optional repeat / reminder fields, leaving the stored values alone when omitted.
    private func apply(_ body: ImportantDateRequest, to importantDate: ImportantDate) {
        if let repeatYearly = body.repeatYearly {
            importantDate.repeatYearly = repeatYearly
        }
        if let reminderEnabled = body.reminderEnabled {
            importantDate.reminderEnabled = reminderEnabled
            importantDate.reminderDaysBefore = reminderEnabled ? max(body.reminderDaysBefore ?? 0, 0) : nil
        }
    }

    private func parseDate(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: string) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD.")
        }
        return date
    }
}
