//
//  DeviceController.swift
//  LuckyStarsBack
//
//  The app tells the server the push address of the phone (after login) and takes it back (on logout).
//

import Vapor
import Fluent

struct DeviceController: RouteCollection {
    private static let environments: Set<String> = ["sandbox", "production"]

    func boot(routes: any RoutesBuilder) throws {
        let devices = routes.grouped("devices").grouped(JWTMiddleware())

        devices.grouped(RateLimitMiddleware(scope: "register-device", limit: 30, window: 60 * 60))
            .put(use: register)
        devices.delete(":token", use: unregister)
    }

    struct RegisterRequest: Content {
        let token: String
        let environment: String
    }

    // MARK: - PUT /devices
    /// Saves the phone's push address for the signed-in user. If the address was saved for someone else
    /// (another person logged in on the same phone before), it moves to this user.
    @Sendable
    func register(req: Request) async throws -> HTTPStatus {
        let userId = try currentUserId(req)
        let body = try req.content.decode(RegisterRequest.self)

        let token = body.token.trimmed.lowercased()
        // A push address is a long string of hex digits. Refuse anything else.
        guard (32...200).contains(token.count), token.allSatisfy(\.isHexDigit) else {
            throw Abort(.badRequest, reason: "Invalid device token.")
        }
        guard Self.environments.contains(body.environment) else {
            throw Abort(.badRequest, reason: "Invalid environment.")
        }

        if let existing = try await DeviceToken.query(on: req.db).filter(\.$token == token).first() {
            existing.userId = userId
            existing.environment = body.environment
            try await existing.save(on: req.db)
        } else {
            let device = DeviceToken(userId: userId, token: token, environment: body.environment)
            do {
                try await device.save(on: req.db)
            } catch let error as any DatabaseError where error.isConstraintFailure {
                // Two requests at once: the other one saved it first. Same end result.
            }
        }
        return .noContent
    }

    // MARK: - DELETE /devices/:token
    @Sendable
    func unregister(req: Request) async throws -> HTTPStatus {
        let userId = try currentUserId(req)
        guard let token = req.parameters.get("token")?.lowercased() else {
            throw Abort(.badRequest, reason: "Missing device token.")
        }

        // Only your own phones: deleting one that isn't yours is silently a no-op.
        try await DeviceToken.query(on: req.db)
            .filter(\.$token == token)
            .filter(\.$userId == userId)
            .delete()
        return .noContent
    }

    private func currentUserId(_ req: Request) throws -> UUID {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }
        return userId
    }
}
