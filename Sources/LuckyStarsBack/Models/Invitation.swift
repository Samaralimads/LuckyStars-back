//
//  Invitation.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Fluent
import Vapor

final class Invitation: Model, @unchecked Sendable {
    static let schema = "invitation"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "invitation_code")
    var invitationCode: String

    @Field(key: "code_used")
    var codeUsed: Bool

    init() {}
}
