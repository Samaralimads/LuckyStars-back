//
//  CoupleDTO.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 30/04/2026.
//

import Vapor

// MARK: - Create Couple Request (User 1)
struct CreateCoupleRequest: Content {
    let relationshipStartDate: String
}

// MARK: - Join Request (User 2)
struct JoinCoupleRequest: Content {
    let invitationCode: String
}

// MARK: - Invitation Response
struct InvitationResponse: Content {
    let code: String
}

// MARK: - Couple Response
struct CoupleResponse: Content {
    let id: UUID
    let relationshipStartDate: String
    let partner: PartnerResponse?
}

struct PartnerResponse: Content {
    let id: UUID
    let firstName: String
}
