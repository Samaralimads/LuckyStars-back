//
//  ProfilePictureController.swift
//  LuckyStarsBack
//
//  Profile photos. The image itself is a file on the server (one JPEG per person); the database only
//  keeps a marker in the existing `user.profile_picture` column, so nothing about the tables changes.
//
//  The photos are NOT public: only the owner, and the owner's partner, can download one, with a
//  signed-in account.
//
//  Where the files go: the folder in the UPLOADS_DIR setting, or "Uploads/" in the server's working
//  directory. Back that folder up with the database: photos live nowhere else.
//

import Vapor
import Fluent

struct ProfilePictureController: RouteCollection {
    private static let maxBytes = 5 * 1024 * 1024

    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("users", "me", "picture").grouped(JWTMiddleware())
        users.get(use: getMine)
        users.grouped(RateLimitMiddleware(scope: "upload-picture", limit: 20, window: 60 * 60))
            .on(.PUT, body: .collect(maxSize: "5mb"), use: upload)
        users.delete(use: remove)

        routes.grouped("couples", "me", "partner", "picture")
            .grouped(JWTMiddleware())
            .get(use: getPartners)
    }

    // MARK: - PUT /users/me/picture   (body: the JPEG bytes)
    @Sendable
    func upload(req: Request) async throws -> HTTPStatus {
        let userId = try currentUserId(req)

        guard let body = req.body.data, body.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "No image was sent.")
        }
        guard body.readableBytes <= Self.maxBytes else {
            throw Abort(.payloadTooLarge, reason: "The photo is too big (5 MB at most).")
        }
        // A JPEG always starts with these three bytes: refuse anything else (the file name never comes from the client).
        guard body.getBytes(at: body.readerIndex, length: 3) == [0xFF, 0xD8, 0xFF] else {
            throw Abort(.unsupportedMediaType, reason: "Please send a JPEG photo.")
        }

        guard let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        try PictureStorage.ensureDirectory(req.application)
        try await req.fileio.writeFile(body, at: PictureStorage.path(for: userId, app: req.application))

        user.profilePicture = PictureStorage.fileName(for: userId)
        try await user.save(on: req.db)
        return .noContent
    }

    // MARK: - GET /users/me/picture
    @Sendable
    func getMine(req: Request) async throws -> Response {
        let userId = try currentUserId(req)
        return try picture(of: userId, req: req)
    }

    // MARK: - DELETE /users/me/picture
    @Sendable
    func remove(req: Request) async throws -> HTTPStatus {
        let userId = try currentUserId(req)
        guard let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }
        PictureStorage.delete(for: userId, app: req.application)
        user.profilePicture = nil
        try await user.save(on: req.db)
        return .noContent
    }

    // MARK: - GET /couples/me/partner/picture
    @Sendable
    func getPartners(req: Request) async throws -> Response {
        let userId = try currentUserId(req)

        guard let couple = try await Couple.forUser(userId, on: req.db) else {
            throw Abort(.notFound, reason: "You are not part of a couple yet.")
        }
        guard let partnerId = couple.partner1Id == userId ? couple.partner2Id : couple.partner1Id else {
            throw Abort(.notFound, reason: "You don't have a partner yet.")
        }
        return try picture(of: partnerId, req: req)
    }

    // MARK: - Helpers
    private func currentUserId(_ req: Request) throws -> UUID {
        let payload = try req.auth.require(UserPayload.self)
        guard let userId = UUID(uuidString: payload.userId) else {
            throw Abort(.unauthorized)
        }
        return userId
    }

    private func picture(of userId: UUID, req: Request) throws -> Response {
        let path = PictureStorage.path(for: userId, app: req.application)
        guard FileManager.default.fileExists(atPath: path) else {
            throw Abort(.notFound, reason: "No photo.")
        }
        let response = req.fileio.streamFile(at: path)
        response.headers.replaceOrAdd(name: .cacheControl, value: "private, no-cache")
        return response
    }
}

/// Where the photo files live. The file name always comes from the person's id, never from the client.
enum PictureStorage {
    static func directory(_ app: Application) -> String {
        let folder = Environment.get("UPLOADS_DIR") ?? (app.directory.workingDirectory + "Uploads")
        return folder.hasSuffix("/") ? folder : folder + "/"
    }

    static func fileName(for userId: UUID) -> String {
        userId.uuidString.lowercased() + ".jpg"
    }

    static func path(for userId: UUID, app: Application) -> String {
        directory(app) + fileName(for: userId)
    }

    static func ensureDirectory(_ app: Application) throws {
        try FileManager.default.createDirectory(atPath: directory(app), withIntermediateDirectories: true)
    }

    static func delete(for userId: UUID, app: Application) {
        try? FileManager.default.removeItem(atPath: path(for: userId, app: app))
    }
}
