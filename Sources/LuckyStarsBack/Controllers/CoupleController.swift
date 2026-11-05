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
        // Pairing codes are 6 digits: without a limit they could be guessed one after the other.
        couples.grouped(RateLimitMiddleware(scope: "join-couple", limit: 10, window: 15 * 60))
            .post("join", use: joinCouple)
        couples.get("me", use: getMyCouple)
        couples.put("me", use: updateMyCouple)
    }

    // MARK: - GET /couples/me/invitation
    @Sendable
    func getMyInvitation(req: Request) async throws -> InvitationResponse {
        let userId = try currentUserId(req)

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
        let userId = try currentUserId(req)
        let body = try req.content.decode(CreateCoupleRequest.self)
        let startDate = try parseStartDate(body.relationshipStartDate)

        // Calling this again (e.g. onboarding was interrupted and repeated) updates the date
        // instead of creating a second couple.
        if let existing = try await Couple.forUser(userId, on: req.db) {
            existing.relationshipStartDate = startDate
            try await existing.save(on: req.db)
            return try await buildResponse(for: existing, currentUserId: userId, db: req.db)
        }

        // Create new couple with only partner1
        let couple = Couple(
            partner1Id: userId,
            partner2Id: nil,
            relationshipStartDate: startDate
        )
        do {
            try await couple.save(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            // A second request created the couple first (unique index on the partner).
            throw Abort(.conflict, reason: "You already have a couple.")
        }

        return try await buildResponse(for: couple, currentUserId: userId, db: req.db)
    }

    // MARK: - POST /couples/join (User 2)
    @Sendable
    func joinCouple(req: Request) async throws -> CoupleResponse {
        let userId = try currentUserId(req)
        let body = try req.content.decode(JoinCoupleRequest.self)

        let code = body.invitationCode.trimmed
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw Abort(.badRequest, reason: "Pairing codes have 6 digits.")
        }

        guard let sql = req.db as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support raw SQL.")
        }

        do {
            try await sql.raw("""
                CALL create_couple_from_invitation(\(bind: code), \(bind: userId.uuidString))
            """).run()
        } catch {
            // The procedure reports what went wrong in its error message.
            let message = "\(error)"
            req.logger.warning("Join couple failed: \(message)")

            if message.contains("own invitation") {
                throw Abort(.badRequest, reason: "That's your own code. Share it with your partner instead.")
            } else if message.contains("already in a couple") {
                throw Abort(.conflict, reason: "You are already part of a couple.")
            } else if message.contains("No open couple") {
                throw Abort(.conflict, reason: "Your partner hasn't finished setting up yet. Please try again in a moment.")
            } else if message.contains("Invalid or already used") {
                throw Abort(.badRequest, reason: "Invalid or already used code. Please check it and try again.")
            }
            throw Abort(.internalServerError, reason: "Couldn't join the couple. Please try again.")
        }

        return try await fetchCoupleForUser(userId: userId, db: req.db)
    }

    // MARK: - GET /couples/me
    @Sendable
    func getMyCouple(req: Request) async throws -> CoupleResponse {
        let userId = try currentUserId(req)
        return try await fetchCoupleForUser(userId: userId, db: req.db)
    }

    // MARK: - PUT /couples/me (either partner edits the anniversary)
    @Sendable
    func updateMyCouple(req: Request) async throws -> CoupleResponse {
        let userId = try currentUserId(req)
        let body = try req.content.decode(UpdateCoupleRequest.self)
        let startDate = try parseStartDate(body.relationshipStartDate)

        guard let couple = try await Couple.forUser(userId, on: req.db) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }

        couple.relationshipStartDate = startDate
        try await couple.save(on: req.db)

        return try await buildResponse(for: couple, currentUserId: userId, db: req.db)
    }

    // MARK: - Helpers
    private func currentUserId(_ req: Request) throws -> UUID {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }
        return userId
    }

    /// "yyyy-MM-dd", not later than tomorrow (a day of slack for time zones ahead of UTC).
    private func parseStartDate(_ string: String) throws -> Date {
        guard let date = DayFormat.make().date(from: string) else {
            throw Abort(.badRequest, reason: "Invalid date format. Expected YYYY-MM-DD.")
        }
        guard date <= Date().addingTimeInterval(60 * 60 * 24) else {
            throw Abort(.badRequest, reason: "The anniversary can't be in the future.")
        }
        return date
    }

    private func fetchCoupleForUser(userId: UUID, db: any Database) async throws -> CoupleResponse {
        guard let couple = try await Couple.forUser(userId, on: db) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }

        return try await buildResponse(for: couple, currentUserId: userId, db: db)
    }

    private func buildResponse(for couple: Couple, currentUserId: UUID, db: any Database) async throws -> CoupleResponse {
        let partnerId = couple.partner1Id == currentUserId ? couple.partner2Id : Optional(couple.partner1Id)

        var partnerResponse: PartnerResponse? = nil
        if let partnerId, let partner = try await User.find(partnerId, on: db) {
            partnerResponse = PartnerResponse(id: try partner.requireID(), firstName: partner.firstName)
        }

        return CoupleResponse(
            id: try couple.requireID(),
            relationshipStartDate: DayFormat.make().string(from: couple.relationshipStartDate),
            partner: partnerResponse
        )
    }
}
