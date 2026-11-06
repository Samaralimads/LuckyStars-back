//
//  AppleAuthController.swift
//  LuckyStarsBack
//
//  POST /auth/apple: sign in or sign up with an Apple identity token.
//
//  1. Check the token really comes from Apple, for this app, and for this sign-in (nonce).
//  2. Known Apple id            -> log in.
//  3. Same verified email       -> link the Apple id to that account, log in.
//  4. Otherwise a new account   -> needs a first name and a birth date; when the app hasn't
//     got them yet the answer is `needsProfile`, and the app asks again with them.
//

import Vapor
import Fluent
import JWT

struct AppleAuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("auth")
            .grouped(RateLimitMiddleware(scope: "apple-sign-in", limit: 20, window: 15 * 60))
            .post("apple", use: signIn)
    }

    // MARK: - POST /auth/apple
    @Sendable
    func signIn(req: Request) async throws -> AppleAuthResponse {
        let body = try req.content.decode(AppleSignInRequest.self)

        guard let bundleId = AppleConfig.bundleId else {
            req.logger.error("APPLE_BUNDLE_ID is not set: Sign in with Apple is disabled.")
            throw Abort(.internalServerError, reason: "Sign in with Apple isn't available right now.")
        }

        // 1. The token must be signed by Apple, made for this app, and not expired.
        let identity: AppleIdentityToken
        do {
            identity = try await req.jwt.apple.verify(body.identityToken, applicationIdentifier: bundleId)
        } catch {
            req.logger.warning("Apple identity token rejected: \(error)")
            throw Abort(.unauthorized, reason: "We couldn't verify your Apple sign-in. Please try again.")
        }

        // The app puts the SHA-256 of a random string in the request to Apple; Apple returns it in the
        // token. A token copied from another sign-in won't match the string this request carries.
        guard identity.nonce == Self.hashedNonce(body.nonce) else {
            req.logger.warning("Apple identity token rejected: nonce mismatch.")
            throw Abort(.unauthorized, reason: "We couldn't verify your Apple sign-in. Please try again.")
        }

        let appleUserId = identity.subject.value
        let email = identity.email?.normalizedEmail
        let emailVerified = identity.emailVerified?.value ?? false

        // 2. Someone who has signed in with Apple before.
        if let user = try await User.query(on: req.db).filter(\.$appleUserId == appleUserId).first() {
            await attachRefreshToken(to: user, code: body.authorizationCode, req: req)
            try await user.save(on: req.db)
            return try await respond(user, isNew: false, req: req)
        }

        // 3. An account with the same email that Apple has verified: it is the same person.
        if let email, emailVerified,
           let user = try await User.query(on: req.db).filter(\.$email == email).first(),
           user.appleUserId == nil {
            user.appleUserId = appleUserId
            await attachRefreshToken(to: user, code: body.authorizationCode, req: req)
            try await user.save(on: req.db)
            return try await respond(user, isNew: false, req: req)
        }

        // 4. A new account.
        guard let email else {
            throw Abort(.badRequest, reason: "Apple didn't share an email address, so we can't create your account.")
        }

        let firstName = (body.firstName ?? "").trimmed
        guard !firstName.isEmpty, let birthDateString = body.birthDate else {
            return AppleAuthResponse(token: nil, user: nil, needsProfile: true, isNewUser: false)
        }
        try Validation.checkName(firstName)

        guard let birthDate = DayFormat.make().date(from: birthDateString), birthDate <= Date() else {
            throw Abort(.badRequest, reason: "Invalid birthDate. Expected YYYY-MM-DD, not in the future.")
        }

        // An account with this email exists but Apple didn't vouch for the email: don't merge them.
        guard try await User.query(on: req.db).filter(\.$email == email).first() == nil else {
            throw Abort(.conflict, reason: "An account with this email already exists. Please sign in with your email and password.")
        }

        let user = User(firstName: firstName, birthDate: birthDate, email: email, password: nil, appleUserId: appleUserId)
        await attachRefreshToken(to: user, code: body.authorizationCode, req: req)

        do {
            try await user.save(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw Abort(.conflict, reason: "An account with this email already exists. Please sign in with your email and password.")
        }

        return try await respond(user, isNew: true, req: req)
    }

    // MARK: - Helpers
    /// SHA-256 of the nonce as lowercase hex: what Apple puts in the identity token.
    static func hashedNonce(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Keeps what Apple needs to revoke the link later (best effort; sign-in works without it).
    private func attachRefreshToken(to user: User, code: String?, req: Request) async {
        guard user.appleRefreshToken == nil, let code else { return }
        user.appleRefreshToken = await AppleAuthService.refreshToken(
            forAuthorizationCode: code,
            client: req.application.client,
            logger: req.logger
        )
    }

    private func respond(_ user: User, isNew: Bool, req: Request) async throws -> AppleAuthResponse {
        let token = try await req.jwt.sign(UserPayload(userId: try user.requireID().uuidString))
        return AppleAuthResponse(token: token, user: try UserResponse(from: user), needsProfile: false, isNewUser: isNew)
    }
}
