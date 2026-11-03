//
//  PasswordResetController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor
import Fluent

struct PasswordResetController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        auth.post("forgot-password", use: forgotPassword)
        auth.post("verify-code", use: verifyCode)
        auth.post("reset-password", use: resetPassword)
    }

    // MARK: - POST /auth/forgot-password
    @Sendable
    func forgotPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ForgotPasswordRequest.self)

        // Always return 200 even if email not found — prevents email enumeration
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == body.email)
            .first()
        else {
            return .ok
        }

        // Invalidate any existing unused codes for this user
        try await PasswordReset.query(on: req.db)
            .filter(\.$userId == user.requireID())
            .filter(\.$used == false)
            .all()
            .asyncForEach { reset in
                reset.used = true
                try await reset.save(on: req.db)
            }

        // Generate a 6-digit code
        let code = String(format: "%06d", Int.random(in: 0..<1000000))
        let expiresAt = Date().addingTimeInterval(60 * 10)

        let reset = PasswordReset(userId: try user.requireID(), code: code, expiresAt: expiresAt)
        try await reset.save(on: req.db)

        // Send email via Brevo
        guard let apiKey = Environment.get("BREVO_API_KEY"),
              let senderEmail = Environment.get("BREVO_SENDER")
        else {
            throw Abort(.internalServerError, reason: "Missing Brevo environment variables.")
        }

        let payload: [String: Any] = [
            "sender": ["email": senderEmail, "name": "Lucky Stars"],
            "to": [["email": user.email, "name": user.firstName]],
            "subject": "Your Lucky Stars password reset code",
            "htmlContent": """
                <html>
                <body style="font-family: sans-serif; padding: 20px;">
                    <h2>Hi \(user.firstName),</h2>
                    <p>You requested a password reset for your Lucky Stars account.</p>
                    <p>Your reset code is:</p>
                    <h1 style="letter-spacing: 8px; color: #FF6B35;">\(code)</h1>
                    <p>This code is valid for <strong>10 minutes</strong>.</p>
                    <p>If you did not request this, you can safely ignore this email.</p>
                    <br>
                    <p>The Lucky Stars Team</p>
                </body>
                </html>
            """
        ]

        var clientReq = ClientRequest(
            method: .POST,
            url: URI(string: "https://api.brevo.com/v3/smtp/email")
        )
        clientReq.headers.add(name: "api-key", value: apiKey)
        clientReq.headers.add(name: "Content-Type", value: "application/json")
        clientReq.body = try .init(data: JSONSerialization.data(withJSONObject: payload))

        let response = try await req.client.send(clientReq)
        req.logger.info("Brevo response: \(response.status.code)")
        if let body = response.body {
            req.logger.info("Brevo body: \(String(buffer: body))")
        }
        guard response.status.code == 201 || response.status.code == 200 else {
            req.logger.error("Brevo error: \(response.status.code)")
            throw Abort(.internalServerError, reason: "Failed to send reset email.")
        }

        return .ok
    }

    // MARK: - POST /auth/verify-code
    @Sendable
    func verifyCode(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(VerifyCodeRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == body.email)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid code.")
        }

        guard let reset = try await PasswordReset.query(on: req.db)
            .filter(\.$userId == user.requireID())
            .filter(\.$code == body.code)
            .filter(\.$used == false)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid code.")
        }

        guard reset.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Code has expired. Please request a new one.")
        }

        return .ok
    }

    // MARK: - POST /auth/reset-password
    @Sendable
    func resetPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ResetPasswordRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == body.email)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid code.")
        }

        guard let reset = try await PasswordReset.query(on: req.db)
            .filter(\.$userId == user.requireID())
            .filter(\.$code == body.code)
            .filter(\.$used == false)
            .first()
        else {
            throw Abort(.badRequest, reason: "Invalid code.")
        }

        guard reset.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Code has expired. Please request a new one.")
        }

        user.password = try Bcrypt.hash(body.newPassword)
        try await user.save(on: req.db)

        reset.used = true
        try await reset.save(on: req.db)

        return .ok
    }
}

// Helper
extension Array {
    func asyncForEach(_ operation: (Element) async throws -> Void) async throws {
        for element in self {
            try await operation(element)
        }
    }
}
