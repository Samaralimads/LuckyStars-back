//
//  AppleAuthDTO.swift
//  LuckyStarsBack
//

import Vapor

// MARK: - Request
struct AppleSignInRequest: Content {
    /// The identity token (a JWT) Apple gave the app.
    let identityToken: String
    /// The random string the app made up before asking Apple; Apple returns its SHA-256 inside the token.
    let nonce: String
    /// One-time code the app got from Apple; exchanged for a token we need to revoke the link later.
    let authorizationCode: String?
    /// Apple only shares the name the very first time, with the app (not inside the token).
    let firstName: String?
    /// Needed to create a new account (the app asks for it on the "finish your profile" screen).
    let birthDate: String?
}

// MARK: - Response
struct AppleAuthResponse: Content {
    /// nil when `needsProfile` is true.
    let token: String?
    let user: UserResponse?
    /// True for a first-time Apple user: the app must ask for the name (if Apple didn't give it)
    /// and the birth date, then send the request again with them.
    let needsProfile: Bool
    /// Whether this request created the account (the app starts onboarding for new accounts).
    let isNewUser: Bool
}
