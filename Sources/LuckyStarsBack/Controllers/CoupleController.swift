//
//  CoupleController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor
import Fluent
import SQLKit

struct CoupleController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let couples = routes.grouped("couples").grouped(JWTMiddleware())

        couples.get("me", "invitation", use: getMyInvitation)
        couples.post("create", use: createCouple)
        couples.post("join", use: joinCouple)
        couples.get("me", use: getMyCouple)
    }

    // MARK: - GET /couples/me/invitation
    @Sendable
    func getMyInvitation(req: Request) async throws -> InvitationResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        guard let invitation = try await Invitation.query(on: req.db)
            .filter(\.$userId == userId)
            .first()
        else {
            throw Abort(.notFound, reason: "No invitation found for this user.")
        }

        return InvitationResponse(code: invitation.invitationCode)
    }

    // MARK: - POST /couples/create (User 1)
    @Sendable
    func createCouple(req: Request) async throws -> CoupleResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let body = try req.content.decode(CreateCoupleRequest.self)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let startDate = formatter.date(from: body.relationshipStartDate) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD.")
        }

        // Check if user already has a couple
        let existing = try await Couple.query(on: req.db)
            .group(.or) {
                $0.filter(\.$partner1Id == userId)
                $0.filter(\.$partner2Id == userId)
            }
            .first()

        if let existing {
            // Update existing couple's start date
            existing.relationshipStartDate = startDate
            try await existing.save(on: req.db)
            return try await buildResponse(for: existing, currentUserId: userId, db: req.db, formatter: formatter)        }

        // Create new couple with only partner1
        let couple = Couple(
            partner1Id: userId,
            partner2Id: nil,
            relationshipStartDate: startDate
        )
        try await couple.save(on: req.db)

        return try await buildResponse(for: couple, currentUserId: userId, db: req.db, formatter: formatter)
    }

    // MARK: - POST /couples/join (User 2)
    @Sendable
    func joinCouple(req: Request) async throws -> CoupleResponse {
        let payload = try req.auth.require(UserPayload.self)
        let body = try req.content.decode(JoinCoupleRequest.self)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        guard let sql = req.db as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support raw SQL.")
        }

        let placeholderDate = formatter.string(from: Date())

        do {
            try await sql.raw("""
                CALL create_couple_from_invitation(\(bind: body.invitationCode), \(bind: payload.userId), \(bind: placeholderDate))
            """).run()
        } catch {
            req.logger.error("Join couple failed: \(error)")
            throw Abort(.badRequest, reason: "Invalid or expired code, or your partner hasn't finished pairing yet. Please try again.")
        }

        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        return try await fetchCoupleForUser(userId: userId, db: req.db, formatter: formatter)
    }

    // MARK: - GET /couples/me
    @Sendable
    func getMyCouple(req: Request) async throws -> CoupleResponse {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return try await fetchCoupleForUser(userId: userId, db: req.db, formatter: formatter)
    }

    // MARK: - Helpers
    private func fetchCoupleForUser(userId: UUID, db: any Database, formatter: DateFormatter) async throws -> CoupleResponse {
        let couples = try await Couple.query(on: db).all()

        guard let couple = couples.first(where: {
            $0.partner1Id == userId || $0.partner2Id == userId
        }) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }

        return try await buildResponse(for: couple, currentUserId: userId, db: db, formatter: formatter)
    }

    private func buildResponse(for couple: Couple, currentUserId: UUID, db: any Database, formatter: DateFormatter) async throws -> CoupleResponse {
        let partnerId = couple.partner1Id == currentUserId ? couple.partner2Id : Optional(couple.partner1Id)

        var partnerResponse: PartnerResponse? = nil
        if let partnerId, let partner = try await User.find(partnerId, on: db) {
            partnerResponse = PartnerResponse(id: try partner.requireID(), firstName: partner.firstName)
        }

        return CoupleResponse(
            id: try couple.requireID(),
            relationshipStartDate: formatter.string(from: couple.relationshipStartDate),
            partner: partnerResponse
        )
    }
}
