//
//  FavoriteController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor
import Fluent

struct FavoriteController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let favorites = routes.grouped("favorites").grouped(JWTMiddleware())

        favorites.get(use: list)
        favorites.post(":activityId", use: add)
        favorites.delete(":activityId", use: remove)
    }

    // MARK: - GET /favorites
    @Sendable
    func list(req: Request) async throws -> [ActivityResponse] {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        let favorites = try await FavoriteActivity.query(on: req.db)
            .filter(\.$userId == userId)
            .all()

        let activityIds = favorites.map { $0.activityId }

        // `IN ()` with no values is invalid SQL: nothing saved means nothing to look up.
        guard !activityIds.isEmpty else { return [] }

        let activities = try await Activity.query(on: req.db)
            .filter(\.$id ~~ activityIds)
            .all()

        let categoryNames = try await ActivityController.categoryNames(on: req.db)

        return try activities.map { try ActivityResponse(from: $0, categoryName: categoryNames[$0.categoryId] ?? "") }
    }

    // MARK: - POST /favorites/:activityId
    @Sendable
    func add(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        guard
            let activityIdString = req.parameters.get("activityId"),
            let activityId = UUID(uuidString: activityIdString)
        else {
            throw Abort(.badRequest, reason: "Invalid activity ID.")
        }

        // Check activity exists
        guard try await Activity.find(activityId, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Activity not found.")
        }

        // Saving something that is already saved is fine: the end state is what the user asked for
        // (a double tap must not show an error).
        let existing = try await FavoriteActivity.query(on: req.db)
            .filter(\.$userId == userId)
            .filter(\.$activityId == activityId)
            .first()

        guard existing == nil else {
            return .ok
        }

        let favorite = FavoriteActivity(userId: userId, activityId: activityId)
        do {
            try await favorite.save(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            // Two taps at once: the unique key (user, activity) let only the first one in.
            return .ok
        }

        return .created
    }

    // MARK: - DELETE /favorites/:activityId
    @Sendable
    func remove(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }

        guard
            let activityIdString = req.parameters.get("activityId"),
            let activityId = UUID(uuidString: activityIdString)
        else {
            throw Abort(.badRequest, reason: "Invalid activity ID.")
        }

        guard let favorite = try await FavoriteActivity.query(on: req.db)
            .filter(\.$userId == userId)
            .filter(\.$activityId == activityId)
            .first()
        else {
            throw Abort(.notFound, reason: "Favorite not found.")
        }

        try await favorite.delete(on: req.db)
        return .noContent
    }
}
