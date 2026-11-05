//
//  UserController.swift
//  LuckyStarsBack
//
//  Created by Samara Lima da Silva on 29/04/2026.
//

import Vapor
import Fluent
import JWT

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("users")

        // Public routes (rate limited: these are what password guessing and sign-up spam go through)
        users.grouped(RateLimitMiddleware(scope: "register", limit: 20, window: 60 * 60))
            .post("register", use: register)
        users.grouped(RateLimitMiddleware(scope: "login", limit: 10, window: 15 * 60))
            .post("login", use: login)

        // Protected routes
        let protected = users.grouped(JWTMiddleware())
        protected.get("me", use: me)
        protected.put("me", use: updateMe)
        protected.delete("me", use: deleteMe)
        protected.grouped(RateLimitMiddleware(scope: "change-password", limit: 10, window: 15 * 60))
            .put("me", "password", use: changePassword)
    }

    // Checked against when the email is unknown, so "no such account" takes as long as "wrong password".
    private static let dummyHash = (try? Bcrypt.hash("Dummy-Password-1")) ?? ""

    // MARK: - Register
    @Sendable
    func register(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(RegisterRequest.self)

        let firstName = body.firstName.trimmed
        let email = body.email.normalizedEmail
        try Validation.checkName(firstName)
        try Validation.checkEmail(email)
        try Validation.checkPassword(body.password)

        guard let birthDate = DayFormat.make().date(from: body.birthDate) else {
            throw Abort(.badRequest, reason: "Invalid birthDate format. Expected YYYY-MM-DD.")
        }
        guard birthDate <= Date() else {
            throw Abort(.badRequest, reason: "Birth date can't be in the future.")
        }

        let existing = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first()

        guard existing == nil else {
            throw Abort(.conflict, reason: "An account with this email already exists.")
        }

        let hashed = try Bcrypt.hash(body.password)
        let user = User(
            firstName: firstName,
            birthDate: birthDate,
            email: email,
            password: hashed
        )

        do {
            try await user.save(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            // Two sign-ups with the same email at the same moment: the unique index lets only one through.
            throw Abort(.conflict, reason: "An account with this email already exists.")
        }

        let token = try await generateToken(for: user, req: req)
        let userResponse = try UserResponse(from: user)
        return AuthResponse(token: token, user: userResponse)
    }

    // MARK: - Login
    @Sendable
    func login(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == body.email.normalizedEmail)
            .first()
        else {
            _ = try? Bcrypt.verify(body.password, created: Self.dummyHash)
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }

        guard try Bcrypt.verify(body.password, created: user.password) else {
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }

        let token = try await generateToken(for: user, req: req)
        let userResponse = try UserResponse(from: user)
        return AuthResponse(token: token, user: userResponse)
    }

    // MARK: - Me
    @Sendable
    func me(req: Request) async throws -> UserResponse {
        let payload = try req.auth.require(UserPayload.self)

        guard
            let uuid = UUID(uuidString: payload.userId),
            let user = try await User.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "User not found.")
        }

        return try UserResponse(from: user)
    }

    // MARK: - Update Me
    @Sendable
    func updateMe(req: Request) async throws -> UserResponse {
        let payload = try req.auth.require(UserPayload.self)

        guard
            let uuid = UUID(uuidString: payload.userId),
            let user = try await User.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let body = try req.content.decode(UpdateUserRequest.self)

        if let firstName = body.firstName {
            let trimmed = firstName.trimmed
            try Validation.checkName(trimmed)
            user.firstName = trimmed
        }
        if let profilePicture = body.profilePicture {
            user.profilePicture = profilePicture
        }
        if let rawEmail = body.email {
            let email = rawEmail.normalizedEmail
            // Only a *changed* email can clash with another account (the app sends the current one on every save).
            // Compared ignoring case: older accounts may be stored with capital letters.
            if email != user.email.normalizedEmail {
                try Validation.checkEmail(email)
                let existing = try await User.query(on: req.db)
                    .filter(\.$email == email)
                    .first()
                guard existing == nil else {
                    throw Abort(.conflict, reason: "This email is already in use.")
                }
                user.email = email
            }
        }

        do {
            try await user.save(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw Abort(.conflict, reason: "This email is already in use.")
        }
        return try UserResponse(from: user)
    }

    // MARK: - Delete Me
    /// Deletes the account. If the user was paired, the partner keeps their account, favorites,
    /// important dates and the couple (now with only them in it), and can pair again.
    @Sendable
    func deleteMe(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)

        guard
            let uuid = UUID(uuidString: payload.userId),
            let user = try await User.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "User not found.")
        }

        try await req.db.transaction { db in
            if let couple = try await Couple.forUser(uuid, on: db) {
                let partnerId = couple.partner1Id == uuid ? couple.partner2Id : couple.partner1Id

                if let partnerId {
                    // Take the deleted user out of the couple *before* deleting them: the database
                    // removes a couple together with either partner, which would take the
                    // partner's side of it too.
                    couple.partner1Id = partnerId
                    couple.partner2Id = nil
                    try await couple.save(on: db)

                    // Proposals still waiting for an answer can never be answered now.
                    try await PlannedActivity.query(on: db)
                        .filter(\.$coupleId == couple.requireID())
                        .filter(\.$bookingStatus == "pending")
                        .set(\.$bookingStatus, to: "rejected")
                        .update()

                    // The partner's invitation code was used up by this pairing; free it for the next one.
                    try await Invitation.query(on: db)
                        .filter(\.$userId == partnerId)
                        .set(\.$codeUsed, to: false)
                        .update()
                }
                // A couple with only this user in it is removed together with the user.
            }

            try await user.delete(on: db)
        }

        return .noContent
    }

    // MARK: - Change Password
    @Sendable
    func changePassword(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)

        guard
            let uuid = UUID(uuidString: payload.userId),
            let user = try await User.find(uuid, on: req.db)
        else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let body = try req.content.decode(ChangePasswordRequest.self)

        // 400, not 401: the app treats any 401 as "session expired" and logs the user out.
        guard try Bcrypt.verify(body.currentPassword, created: user.password) else {
            throw Abort(.badRequest, reason: "Current password is incorrect.")
        }
        try Validation.checkPassword(body.newPassword)

        user.password = try Bcrypt.hash(body.newPassword)
        try await user.save(on: req.db)
        return .noContent
    }

    // MARK: - Helpers
    private func generateToken(for user: User, req: Request) async throws -> String {
        let payload = UserPayload(userId: try user.requireID().uuidString)
        return try await req.jwt.sign(payload)
    }
}
