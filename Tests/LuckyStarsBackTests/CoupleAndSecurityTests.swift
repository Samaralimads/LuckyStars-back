@testable import LuckyStarsBack
import VaporTesting
import Testing
import Fluent
import JWT
import Foundation

// Needs a test database with Database/schema.sql and Database/seed.sql loaded (see README).
// Each test creates its own users (random emails) and removes them afterwards.
@Suite("Couples and security", .serialized)
struct CoupleAndSecurityTests {

    // MARK: - Helpers
    struct TestUser {
        let id: UUID
        let email: String
        let token: String
    }

    private func withApp(_ test: (Application, UserBox) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        let users = UserBox()
        do {
            await RateLimiter.shared.reset()
            try await configure(app)
            try await test(app, users)
        } catch {
            try? await users.cleanUp(on: app.db)
            try await app.asyncShutdown()
            throw error
        }
        try? await users.cleanUp(on: app.db)
        try await app.asyncShutdown()
    }

    /// Remembers the users a test created, so they are deleted afterwards.
    final class UserBox: @unchecked Sendable {
        var emails: [String] = []

        func cleanUp(on db: any Database) async throws {
            guard !emails.isEmpty else { return }
            try await User.query(on: db).filter(\.$email ~~ emails).delete()
        }
    }

    private func register(_ app: Application, _ users: UserBox) async throws -> TestUser {
        let email = "test-\(UUID().uuidString.lowercased())@example.com"
        users.emails.append(email)
        let request = RegisterRequest(firstName: "Test", birthDate: "1995-05-20", email: email, password: "Password1")

        var result: TestUser?
        try await app.testing().test(.POST, "users/register", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { res async throws in
            #expect(res.status == .ok)
            let auth = try res.content.decode(AuthResponse.self)
            result = TestUser(id: auth.user.id, email: email, token: auth.token)
        })
        return try #require(result)
    }

    /// Sends a request, returns its status and body.
    private func send(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        as user: TestUser? = nil,
        body: (any Content)? = nil
    ) async throws -> (status: HTTPStatus, body: Data) {
        var status: HTTPStatus = .internalServerError
        var data = Data()
        try await app.testing().test(method, path, beforeRequest: { req in
            if let user { req.headers.bearerAuthorization = BearerAuthorization(token: user.token) }
            if let body { try req.content.encode(body) }
        }, afterResponse: { res async throws in
            status = res.status
            data = Data(res.body.readableBytesView)
        })
        return (status, data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// `first` creates the couple, `second` joins it with first's pairing code.
    private func pair(_ app: Application, _ first: TestUser, _ second: TestUser) async throws {
        let created = try await send(app, .POST, "couples/create", as: first, body: CreateCoupleRequest(relationshipStartDate: "2022-06-15"))
        #expect(created.status == .ok)

        let invitation = try await send(app, .GET, "couples/me/invitation", as: first)
        let code = try decode(InvitationResponse.self, from: invitation.body).code

        let joined = try await send(app, .POST, "couples/join", as: second, body: JoinCoupleRequest(invitationCode: code))
        #expect(joined.status == .ok)
    }

    private func futureDateTime(days: Int = 3) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date().addingTimeInterval(Double(days) * 86_400))
    }

    // MARK: - Tokens
    @Test("A garbage token is a 401, not a 500")
    func garbageTokenIsUnauthorized() async throws {
        try await withApp { app, _ in
            let user = TestUser(id: UUID(), email: "", token: "not.a.token")
            let response = try await send(app, .GET, "users/me", as: user)
            #expect(response.status == .unauthorized)
        }
    }

    @Test("An expired token is a 401")
    func expiredTokenIsUnauthorized() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)

            var payload = UserPayload(userId: user.id.uuidString)
            payload.exp = ExpirationClaim(value: Date().addingTimeInterval(-60))
            let token = try await app.jwt.keys.sign(payload)

            let response = try await send(app, .GET, "users/me", as: TestUser(id: user.id, email: user.email, token: token))
            #expect(response.status == .unauthorized)
        }
    }

    // MARK: - Profile
    @Test("Saving the profile with the unchanged email works")
    func profileSaveWithSameEmail() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            let body = UpdateUserRequest(firstName: "Renamed", email: user.email, profilePicture: nil)
            let response = try await send(app, .PUT, "users/me", as: user, body: body)
            #expect(response.status == .ok)
            #expect(try decode(UserResponse.self, from: response.body).firstName == "Renamed")
        }
    }

    @Test("Emails are matched ignoring case and spaces")
    func loginIgnoresEmailCase() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            let body = LoginRequest(email: "  " + user.email.uppercased() + " ", password: "Password1")
            let response = try await send(app, .POST, "users/login", body: body)
            #expect(response.status == .ok)
        }
    }

    // MARK: - Password reset
    @Test("A reset code locks after too many wrong guesses")
    func resetCodeLocksAfterWrongGuesses() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)

            let forgot = try await send(app, .POST, "auth/forgot-password", body: ForgotPasswordRequest(email: user.email))
            #expect(forgot.status == .ok)

            let reset = try #require(try await PasswordReset.query(on: app.db).filter(\.$userId == user.id).first())
            let wrong = reset.code == "000000" ? "111111" : "000000"

            for _ in 0..<5 {
                let attempt = try await send(app, .POST, "auth/verify-code", body: VerifyCodeRequest(email: user.email, code: wrong))
                #expect(attempt.status == .badRequest)
            }

            // Even the right code no longer works: a new one has to be requested.
            let afterLock = try await send(app, .POST, "auth/verify-code", body: VerifyCodeRequest(email: user.email, code: reset.code))
            #expect(afterLock.status == .badRequest)
        }
    }

    @Test("Resetting with the right code works and sets the new password")
    func resetPasswordWorks() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            _ = try await send(app, .POST, "auth/forgot-password", body: ForgotPasswordRequest(email: user.email))
            let reset = try #require(try await PasswordReset.query(on: app.db).filter(\.$userId == user.id).first())

            let weak = try await send(app, .POST, "auth/reset-password", body: ResetPasswordRequest(email: user.email, code: reset.code, newPassword: "short"))
            #expect(weak.status == .badRequest)

            let ok = try await send(app, .POST, "auth/reset-password", body: ResetPasswordRequest(email: user.email, code: reset.code, newPassword: "NewPassword2"))
            #expect(ok.status == .ok)

            let login = try await send(app, .POST, "users/login", body: LoginRequest(email: user.email, password: "NewPassword2"))
            #expect(login.status == .ok)
        }
    }

    // MARK: - Pairing
    @Test("Your own pairing code can't be used to join")
    func cannotJoinOwnCode() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            _ = try await send(app, .POST, "couples/create", as: user, body: CreateCoupleRequest(relationshipStartDate: "2022-06-15"))
            let invitation = try await send(app, .GET, "couples/me/invitation", as: user)
            let code = try decode(InvitationResponse.self, from: invitation.body).code

            let response = try await send(app, .POST, "couples/join", as: user, body: JoinCoupleRequest(invitationCode: code))
            #expect(response.status == .badRequest)
        }
    }

    @Test("A pairing code works once")
    func codeCannotBeReused() async throws {
        try await withApp { app, users in
            let first = try await register(app, users)
            let second = try await register(app, users)
            let third = try await register(app, users)
            try await pair(app, first, second)

            let invitation = try await send(app, .GET, "couples/me/invitation", as: first)
            let code = try decode(InvitationResponse.self, from: invitation.body).code

            let response = try await send(app, .POST, "couples/join", as: third, body: JoinCoupleRequest(invitationCode: code))
            #expect(response.status == .badRequest)
        }
    }

    @Test("Pairing codes have 6 digits")
    func badCodeFormat() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            let response = try await send(app, .POST, "couples/join", as: user, body: JoinCoupleRequest(invitationCode: "12ab56"))
            #expect(response.status == .badRequest)
        }
    }

    // MARK: - Anniversary
    @Test("Either partner can change the anniversary, and it can't be in the future")
    func updateAnniversary() async throws {
        try await withApp { app, users in
            let first = try await register(app, users)
            let second = try await register(app, users)
            try await pair(app, first, second)

            let changed = try await send(app, .PUT, "couples/me", as: second, body: UpdateCoupleRequest(relationshipStartDate: "2021-01-02"))
            #expect(changed.status == .ok)
            #expect(try decode(CoupleResponse.self, from: changed.body).relationshipStartDate == "2021-01-02")

            let seenByFirst = try await send(app, .GET, "couples/me", as: first)
            #expect(try decode(CoupleResponse.self, from: seenByFirst.body).relationshipStartDate == "2021-01-02")

            let future = try await send(app, .PUT, "couples/me", as: first, body: UpdateCoupleRequest(relationshipStartDate: "2999-01-01"))
            #expect(future.status == .badRequest)

            let badFormat = try await send(app, .PUT, "couples/me", as: first, body: UpdateCoupleRequest(relationshipStartDate: "02/01/2021"))
            #expect(badFormat.status == .badRequest)
        }
    }

    @Test("Changing the anniversary without a couple is a 404")
    func updateAnniversaryWithoutCouple() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            let response = try await send(app, .PUT, "couples/me", as: user, body: UpdateCoupleRequest(relationshipStartDate: "2021-01-02"))
            #expect(response.status == .notFound)
        }
    }

    // MARK: - Proposals
    @Test("You can't accept your own proposal, your partner can")
    func selfAcceptIsForbidden() async throws {
        try await withApp { app, users in
            let first = try await register(app, users)
            let second = try await register(app, users)
            try await pair(app, first, second)

            let activity = try #require(try await Activity.query(on: app.db).first(), "Load Database/seed.sql into the test database.")
            let proposal = ProposeActivityRequest(
                activityId: try activity.requireID(),
                proposedDate: futureDateTime(),
                reminderEnabled: false,
                reminderDaysBefore: nil
            )
            let proposed = try await send(app, .POST, "planned-activities", as: first, body: proposal)
            #expect(proposed.status == .ok)
            let plannedId = try decode(PlannedActivityResponse.self, from: proposed.body).id

            let own = try await send(app, .PUT, "planned-activities/\(plannedId)/accept", as: first)
            #expect(own.status == .forbidden)

            let partner = try await send(app, .PUT, "planned-activities/\(plannedId)/accept", as: second)
            #expect(partner.status == .ok)

            let again = try await send(app, .PUT, "planned-activities/\(plannedId)/accept", as: second)
            #expect(again.status == .conflict)
        }
    }

    @Test("Nobody to answer yet: proposing before your partner joined is refused")
    func cannotProposeBeforePairing() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)
            _ = try await send(app, .POST, "couples/create", as: user, body: CreateCoupleRequest(relationshipStartDate: "2022-06-15"))

            let activity = try #require(try await Activity.query(on: app.db).first(), "Load Database/seed.sql into the test database.")
            let proposal = ProposeActivityRequest(
                activityId: try activity.requireID(),
                proposedDate: futureDateTime(),
                reminderEnabled: false,
                reminderDaysBefore: nil
            )
            let response = try await send(app, .POST, "planned-activities", as: user, body: proposal)
            #expect(response.status == .conflict)
        }
    }

    // MARK: - Account deletion
    @Test("Deleting an account keeps the partner, their couple and their pairing code")
    func deleteKeepsPartner() async throws {
        try await withApp { app, users in
            let first = try await register(app, users)
            let second = try await register(app, users)
            try await pair(app, first, second)

            let deleted = try await send(app, .DELETE, "users/me", as: first)
            #expect(deleted.status == .noContent)

            // The partner is still there, still has the couple, now on their own.
            let couple = try await send(app, .GET, "couples/me", as: second)
            #expect(couple.status == .ok)
            #expect(try decode(CoupleResponse.self, from: couple.body).partner == nil)

            let me = try await send(app, .GET, "users/me", as: second)
            #expect(me.status == .ok)

            // Their pairing code is free again for the next partner.
            let invitation = try #require(try await Invitation.query(on: app.db).filter(\.$userId == second.id).first())
            #expect(invitation.codeUsed == false)

            // The deleted account's token stops working.
            let stale = try await send(app, .GET, "users/me", as: first)
            #expect(stale.status == .unauthorized)
        }
    }

    // MARK: - Favorites
    @Test("Saving a favorite twice is fine, and an empty list is an empty list")
    func favoritesAreIdempotent() async throws {
        try await withApp { app, users in
            let user = try await register(app, users)

            let empty = try await send(app, .GET, "favorites", as: user)
            #expect(empty.status == .ok)
            #expect(try decode([ActivityResponse].self, from: empty.body).isEmpty)

            let activity = try #require(try await Activity.query(on: app.db).first(), "Load Database/seed.sql into the test database.")
            let id = try activity.requireID()

            let first = try await send(app, .POST, "favorites/\(id)", as: user)
            #expect(first.status == .created)
            let second = try await send(app, .POST, "favorites/\(id)", as: user)
            #expect(second.status == .ok)
        }
    }

    // MARK: - Rate limits
    @Test("Too many login attempts are answered with 429")
    func loginIsRateLimited() async throws {
        try await withApp { app, _ in
            let body = LoginRequest(email: "nobody@example.com", password: "Password1")
            for _ in 0..<10 {
                let attempt = try await send(app, .POST, "users/login", body: body)
                #expect(attempt.status == .unauthorized)
            }
            let blocked = try await send(app, .POST, "users/login", body: body)
            #expect(blocked.status == .tooManyRequests)
        }
    }
}
