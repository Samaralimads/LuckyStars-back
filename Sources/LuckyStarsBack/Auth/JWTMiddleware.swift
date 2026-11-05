//
//  JWTMiddleware.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Vapor
import Fluent
import JWT

struct JWTMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing token.")
        }

        // A bad, tampered or expired token is a 401 (the app logs out on 401), never a 500.
        let payload: UserPayload
        do {
            payload = try await request.jwt.verify(token, as: UserPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired token.")
        }

        // A token outlives the account it was issued for (30 days): refuse it once the user is gone.
        guard let userId = UUID(uuidString: payload.userId),
              try await User.find(userId, on: request.db) != nil
        else {
            throw Abort(.unauthorized, reason: "Invalid or expired token.")
        }

        request.auth.login(payload)

        return try await next.respond(to: request)
    }
}
