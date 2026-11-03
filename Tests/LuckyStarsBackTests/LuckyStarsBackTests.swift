@testable import LuckyStarsBack
import VaporTesting
import Testing
import Fluent
import Foundation

@Suite("App Tests with DB", .serialized)
struct LuckyStarsBackTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Root route reports the API is running")
    func rootRoute() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "/", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "Lucky Stars API is running.")
            })
        }
    }

    // NOTE: this suite runs against a real, shared dev database (no isolated
    // test DB / migrations to reset between runs), so every test uses
    // randomly-suffixed data and cleans up after itself rather than assuming
    // an empty table or asserting on exact row counts.

    @Test("Listing categories includes newly created ones")
    func getAllCategories() async throws {
        try await withApp { app in
            let suffix = UUID().uuidString.prefix(8)
            let names = ["Test Category A \(suffix)", "Test Category B \(suffix)"]
            let categories = names.map { name -> LuckyStarsBack.Category in
                let category = LuckyStarsBack.Category()
                category.name = name
                return category
            }
            try await categories.create(on: app.db)

            do {
                try await app.testing().test(.GET, "categories", afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let decoded = try res.content.decode([CategoryResponse].self)
                    #expect(names.allSatisfy { name in decoded.contains { $0.name == name } })
                })
            } catch {
                try? await categories.delete(on: app.db)
                throw error
            }

            try await categories.delete(on: app.db)
        }
    }

    @Test("Registering a new user creates it and returns a token")
    func registerUser() async throws {
        try await withApp { app in
            let request = RegisterRequest(
                firstName: "Sam",
                birthDate: "1995-05-20",
                email: "sam-\(UUID().uuidString)@example.com",
                password: "Password1"
            )

            do {
                try await app.testing().test(.POST, "users/register", beforeRequest: { req in
                    try req.content.encode(request)
                }, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let auth = try res.content.decode(AuthResponse.self)
                    #expect(auth.user.email == request.email)
                    #expect(!auth.token.isEmpty)

                    let users = try await User.query(on: app.db)
                        .filter(\.$email == request.email)
                        .all()
                    #expect(users.count == 1)
                })
            } catch {
                try? await User.query(on: app.db).filter(\.$email == request.email).delete()
                throw error
            }

            try await User.query(on: app.db).filter(\.$email == request.email).delete()
        }
    }

    @Test("Registering with an email already in use is rejected")
    func registerDuplicateEmail() async throws {
        try await withApp { app in
            let email = "dup-\(UUID().uuidString)@example.com"
            let existing = User(firstName: "Sam", birthDate: Date(), email: email, password: "hashed")
            try await existing.save(on: app.db)

            let request = RegisterRequest(
                firstName: "Alex",
                birthDate: "1990-01-01",
                email: email,
                password: "Password1"
            )

            do {
                try await app.testing().test(.POST, "users/register", beforeRequest: { req in
                    try req.content.encode(request)
                }, afterResponse: { res async in
                    #expect(res.status == .conflict)
                })
            } catch {
                try? await existing.delete(on: app.db)
                throw error
            }

            try await existing.delete(on: app.db)
        }
    }

    @Test("Deleting the authenticated user's account removes it")
    func deleteAccount() async throws {
        try await withApp { app in
            let request = RegisterRequest(
                firstName: "Sam",
                birthDate: "1995-05-20",
                email: "delete-me-\(UUID().uuidString)@example.com",
                password: "Password1"
            )

            var token = ""
            try await app.testing().test(.POST, "users/register", beforeRequest: { req in
                try req.content.encode(request)
            }, afterResponse: { res async throws in
                token = try res.content.decode(AuthResponse.self).token
            })

            do {
                try await app.testing().test(.DELETE, "users/me", beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                }, afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    let users = try await User.query(on: app.db)
                        .filter(\.$email == request.email)
                        .all()
                    #expect(users.isEmpty)
                })
            } catch {
                try? await User.query(on: app.db).filter(\.$email == request.email).delete()
                throw error
            }
        }
    }
}
