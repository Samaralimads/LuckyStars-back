//
//  JWTMiddleware.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Vapor
import JWT

struct JWTMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing token.")
        }

        let payload = try await request.jwt.verify(token, as: UserPayload.self)
        request.auth.login(payload)

        return try await next.respond(to: request)
    }
}
