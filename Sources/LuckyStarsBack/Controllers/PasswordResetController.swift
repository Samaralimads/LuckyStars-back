//
//  PasswordResetController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 13/05/2026.
//

import Vapor
import Fluent

struct PasswordResetController: RouteCollection {
    /// Wrong guesses allowed per code before it is locked. A 6-digit code has only a million
    /// values, so without a limit it could be guessed within its 10 minutes.
    private static let maxAttempts = 5
    /// Minimum time between two reset emails for the same account.
    private static let resendCooldown: TimeInterval = 60

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        auth.grouped(RateLimitMiddleware(scope: "forgot-password", limit: 5, window: 15 * 60))
            .post("forgot-password", use: forgotPassword)
        auth.grouped(RateLimitMiddleware(scope: "verify-code", limit: 15, window: 15 * 60))
            .post("verify-code", use: verifyCode)
        auth.grouped(RateLimitMiddleware(scope: "reset-password", limit: 15, window: 15 * 60))
            .post("reset-password", use: resetPassword)
    }

    // MARK: - POST /auth/forgot-password
    @Sendable
    func forgotPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ForgotPasswordRequest.self)

        // Every outcome answers 200 after about the same work (the email goes out in the
        // background), so the response never tells whether an email has an account.
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == body.email.normalizedEmail)
            .first()
        else {
            return .ok
        }
        let userId = try user.requireID()

        // One email a minute per account: stops someone flooding a person's inbox.
        if let latest = try await PasswordReset.query(on: req.db)
            .filter(\.$userId == userId)
            .sort(\.$createdAt, .descending)
            .first(),
           let created = latest.createdAt,
           Date().timeIntervalSince(created) < Self.resendCooldown {
            return .ok
        }

        // Invalidate any existing unused codes for this user
        try await PasswordReset.query(on: req.db)
            .filter(\.$userId == userId)
            .filter(\.$used == false)
            .set(\.$used, to: true)
            .update()

        // Generate a 6-digit code
        let code = String(format: "%06d", Int.random(in: 0..<1000000))
        let expiresAt = Date().addingTimeInterval(60 * 10)

        let reset = PasswordReset(userId: userId, code: code, expiresAt: expiresAt)
        try await reset.save(on: req.db)

        let client = req.application.client
        let logger = req.logger
        let firstName = user.firstName
        let toEmail = user.email
        Task {
            await Self.sendResetEmail(code: code, firstName: firstName, to: toEmail, client: client, logger: logger)
        }

        return .ok
    }

    // MARK: - POST /auth/verify-code
    @Sendable
    func verifyCode(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(VerifyCodeRequest.self)
        _ = try await findValidReset(email: body.email, code: body.code, db: req.db)
        return .ok
    }

    // MARK: - POST /auth/reset-password
    @Sendable
    func resetPassword(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(ResetPasswordRequest.self)
        try Validation.checkPassword(body.newPassword)

        let (user, reset) = try await findValidReset(email: body.email, code: body.code, db: req.db)
        let hashed = try Bcrypt.hash(body.newPassword)

        try await req.db.transaction { db in
            user.password = hashed
            try await user.save(on: db)

            reset.used = true
            try await reset.save(on: db)
        }

        return .ok
    }

    // MARK: - Helpers
    /// The latest unused code of this account, if `code` matches it and it hasn't expired.
    /// Wrong guesses are counted; after `maxAttempts` the code is locked and a new one must be requested.
    private func findValidReset(email: String, code: String, db: any Database) async throws -> (User, PasswordReset) {
        let invalid = Abort(.badRequest, reason: "Invalid code.")

        guard let user = try await User.query(on: db)
            .filter(\.$email == email.normalizedEmail)
            .first()
        else {
            throw invalid
        }

        guard let reset = try await PasswordReset.query(on: db)
            .filter(\.$userId == user.requireID())
            .filter(\.$used == false)
            .sort(\.$createdAt, .descending)
            .first()
        else {
            throw invalid
        }

        guard reset.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Code has expired. Please request a new one.")
        }

        guard reset.code == code.trimmed else {
            reset.attempts += 1
            let locked = reset.attempts >= Self.maxAttempts
            if locked { reset.used = true }
            try await reset.save(on: db)

            if locked {
                throw Abort(.badRequest, reason: "Too many wrong attempts. Please request a new code.")
            }
            throw invalid
        }

        return (user, reset)
    }

    /// Sends the code through Brevo. Failures are logged, never returned to the caller.
    private static func sendResetEmail(code: String, firstName: String, to email: String, client: any Client, logger: Logger) async {
        guard let apiKey = Environment.get("BREVO_API_KEY"),
              let senderEmail = Environment.get("BREVO_SENDER")
        else {
            logger.error("Password reset email not sent: BREVO_API_KEY / BREVO_SENDER are not set.")
            return
        }

        let payload: [String: Any] = [
            "sender": ["email": senderEmail, "name": "Lucky Stars"],
            "to": [["email": email, "name": firstName]],
            "subject": "Your Lucky Stars password reset code",
            "htmlContent": """
                <html>
                <body style="font-family: sans-serif; padding: 20px;">
                    <h2>Hi \(firstName.htmlEscaped),</h2>
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

        do {
            var clientReq = ClientRequest(
                method: .POST,
                url: URI(string: "https://api.brevo.com/v3/smtp/email")
            )
            clientReq.headers.add(name: "api-key", value: apiKey)
            clientReq.headers.add(name: "Content-Type", value: "application/json")
            clientReq.body = try .init(data: JSONSerialization.data(withJSONObject: payload))

            let response = try await client.send(clientReq)
            guard response.status.code == 201 || response.status.code == 200 else {
                logger.error("Brevo error: \(response.status.code)")
                return
            }
            logger.debug("Brevo accepted the reset email: \(response.status.code)")
        } catch {
            logger.error("Sending the reset email failed: \(error)")
        }
    }
}
