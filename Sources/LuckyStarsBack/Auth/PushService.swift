//
//  PushService.swift
//  LuckyStarsBack
//
//  Sends push notifications through Apple (APNs) to the phones of a user.
//
//  Uses the same Apple key as Sign in with Apple, if that key also has "Apple Push Notifications service"
//  ticked in the Apple Developer portal. Settings: APPLE_BUNDLE_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY.
//
//  A push that fails never breaks the request that caused it: it is logged and forgotten.
//

import Vapor
import Fluent
import JWT

/// What happened, so the notification says the right thing.
/// The activity's name is not in the text: a notification cuts long titles, so it adds little.
enum PushEvent: Sendable {
    case proposed
    case accepted
    case declined
    case rescheduled
    case paired

    /// `name` is the first name of the person who did it.
    func message(from name: String) -> (title: String, body: String, kind: String) {
        switch self {
        case .proposed:
            return ("\(name) proposed an activity", "Open Lucky Stars to reply.", "proposal")
        case .accepted:
            return ("\(name) accepted your proposal", "Open Lucky Stars to see it.", "reply")
        case .declined:
            return ("\(name) can't make it", "Open Lucky Stars to see.", "reply")
        case .rescheduled:
            return ("\(name) suggested a new time", "Open Lucky Stars to reply.", "reply")
        case .paired:
            return ("\(name) joined you", "You're paired. Time to plan your first date.", "paired")
        }
    }
}

private struct APNsProviderClaims: JWTPayload {
    var iss: IssuerClaim
    var iat: IssuedAtClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {}
}

/// Apple wants the same signed token reused for a while (not made fresh for every push), at most an hour.
private actor APNsTokenCache {
    static let shared = APNsTokenCache()
    private var cached: (token: String, created: Date)?

    func token() async throws -> String {
        if let cached, Date().timeIntervalSince(cached.created) < 40 * 60 {
            return cached.token
        }
        guard let teamId = AppleConfig.teamId,
              let keyId = AppleConfig.keyId,
              let pem = AppleConfig.privateKey
        else {
            throw Abort(.internalServerError, reason: "Push notifications are not configured.")
        }

        let kid = JWKIdentifier(string: keyId)
        let keys = JWTKeyCollection()
        await keys.add(ecdsa: try ES256PrivateKey(pem: pem), kid: kid)
        let fresh = try await keys.sign(
            APNsProviderClaims(iss: .init(value: teamId), iat: .init(value: Date())),
            kid: kid
        )
        cached = (fresh, Date())
        return fresh
    }
}

private struct APNsPayload: Encodable {
    struct Aps: Encodable {
        struct Alert: Encodable {
            let title: String
            let body: String
        }
        let alert: Alert
        let sound: String
        let badge: Int
    }
    let aps: Aps
    /// "proposal", "reply" or "paired": lets the app open the right screen when the notification is tapped.
    let kind: String
}

private struct APNsErrorResponse: Decodable {
    let reason: String
}

enum PushService {
    /// Tells the partner of `userId` what `userId` just did. Runs in the background and never throws.
    static func notifyPartner(of userId: UUID, event: PushEvent, app: Application) {
        Task {
            do {
                guard let couple = try await Couple.forUser(userId, on: app.db),
                      let partnerId = couple.partner1Id == userId ? couple.partner2Id : couple.partner1Id,
                      let user = try await User.find(userId, on: app.db)
                else { return }

                let message = event.message(from: user.firstName)
                await send(title: message.title, body: message.body, kind: message.kind, to: partnerId, app: app)
            } catch {
                app.logger.warning("Push notification skipped: \(error)")
            }
        }
    }

    /// Sends to every phone of `userId`.
    static func send(title: String, body: String, kind: String, to userId: UUID, app: Application) async {
        guard AppleConfig.canTalkToApple, let bundleId = AppleConfig.bundleId else {
            app.logger.warning("Push notification not sent: the APPLE_* settings are not all set.")
            return
        }

        do {
            let devices = try await DeviceToken.query(on: app.db).filter(\.$userId == userId).all()
            guard !devices.isEmpty else { return }

            let payload = APNsPayload(
                aps: .init(
                    alert: .init(title: title, body: body),
                    sound: "default",
                    badge: try await pendingCount(for: userId, db: app.db)
                ),
                kind: kind
            )
            let providerToken = try await APNsTokenCache.shared.token()

            for device in devices {
                await deliver(payload, to: device, bundleId: bundleId, providerToken: providerToken, app: app)
            }
        } catch {
            app.logger.warning("Push notification failed: \(error)")
        }
    }

    /// The number on the app icon: proposals from the partner that still wait for an answer.
    static func pendingCount(for userId: UUID, db: any Database) async throws -> Int {
        guard let couple = try await Couple.forUser(userId, on: db) else { return 0 }
        return try await PlannedActivity.query(on: db)
            .filter(\.$coupleId == couple.requireID())
            .filter(\.$bookingStatus == "pending")
            .filter(\.$plannedByUserId != userId)
            .count()
    }

    private static func deliver(
        _ payload: APNsPayload,
        to device: DeviceToken,
        bundleId: String,
        providerToken: String,
        app: Application
    ) async {
        // Builds from Xcode use Apple's sandbox, TestFlight and the App Store use production.
        let host = device.environment == "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "bearer \(providerToken)")
        headers.add(name: "apns-topic", value: bundleId)
        headers.add(name: "apns-push-type", value: "alert")
        headers.add(name: "apns-priority", value: "10")

        do {
            let response = try await app.client.post(
                URI(string: "https://\(host)/3/device/\(device.token)"),
                headers: headers
            ) { request in
                try request.content.encode(payload, as: .json)
            }

            guard response.status != .ok else { return }

            let reason = (try? response.content.decode(APNsErrorResponse.self))?.reason ?? "unknown"
            app.logger.warning("APNs refused a push: \(response.status.code) \(reason)")

            // The phone is gone (app deleted, or a token from the other Apple environment): forget it.
            if response.status == .gone || ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].contains(reason) {
                try? await device.delete(on: app.db)
            }
        } catch {
            app.logger.warning("APNs request failed: \(error)")
        }
    }
}
