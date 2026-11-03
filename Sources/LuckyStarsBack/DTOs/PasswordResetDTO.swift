//
//  PasswordResetDTO.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor

struct ForgotPasswordRequest: Content {
    let email: String
}

struct VerifyCodeRequest: Content {
    let email: String
    let code: String
}

struct ResetPasswordRequest: Content {
    let email: String
    let code: String
    let newPassword: String
}
