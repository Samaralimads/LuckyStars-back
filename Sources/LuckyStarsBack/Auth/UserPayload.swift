//
//  UserPayload.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import JWT
import Vapor
import Foundation

struct UserPayload: JWTPayload, Authenticatable {
    var userId: String
    var exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }

    init(userId: String) {
        self.userId = userId
        self.exp = ExpirationClaim(value: Date.now.addingTimeInterval(60 * 60 * 24 * 30))
    }
}
