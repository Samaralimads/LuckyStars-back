//
//  AppleAuthService.swift
//  LuckyStarsBack
//
//  Talks to Apple's servers for Sign in with Apple: turns the one-time authorization code into a
//  refresh token (kept to revoke the link later), and revokes it when an account is deleted.
//
//  Needs these environment variables (from the Apple Developer portal):
//    APPLE_BUNDLE_ID    the app's bundle identifier (always needed: checks tokens were made for this app)
//    APPLE_TEAM_ID      your Team ID
//    APPLE_KEY_ID       the Key ID of a "Sign in with Apple" key
//    APPLE_PRIVATE_KEY  the contents of that key's .p8 file (newlines may be written as \n)
//  Without the last three, sign-in still works; the link just can't be revoked.
//

import Vapor
import JWT

enum AppleConfig {
    static var bundleId: String? { Environment.get("APPLE_BUNDLE_ID") }
    static var teamId: String? { Environment.get("APPLE_TEAM_ID") }
    static var keyId: String? { Environment.get("APPLE_KEY_ID") }
    static var privateKey: String? {
        Environment.get("APPLE_PRIVATE_KEY")?.replacingOccurrences(of: "\\n", with: "\n")
    }

    static var canTalkToApple: Bool {
        bundleId != nil && teamId != nil && keyId != nil && privateKey != nil
    }
}

/// The "client secret" Apple wants: a short-lived JWT signed with your .p8 key.
private struct AppleClientSecret: JWTPayload {
    var iss: IssuerClaim
    var iat: IssuedAtClaim
    var exp: ExpirationClaim
    var aud: AudienceClaim
    var sub: SubjectClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {}
}

private struct AppleTokenRequest: Content {
    let client_id: String
    let client_secret: String
    let code: String
    let grant_type: String
}

private struct AppleTokenResponse: Content {
    let refresh_token: String?
}

private struct AppleRevokeRequest: Content {
    let client_id: String
    let client_secret: String
    let token: String
    let token_type_hint: String
}

enum AppleAuthService {
    private static let audience = "https://appleid.apple.com"

    private static func clientSecret() async throws -> String {
        guard let bundleId = AppleConfig.bundleId,
              let teamId = AppleConfig.teamId,
              let keyId = AppleConfig.keyId,
              let pem = AppleConfig.privateKey
        else {
            throw Abort(.internalServerError, reason: "Sign in with Apple is not fully configured.")
        }

        let kid = JWKIdentifier(string: keyId)
        let keys = JWTKeyCollection()
        await keys.add(ecdsa: try ES256PrivateKey(pem: pem), kid: kid)

        let claims = AppleClientSecret(
            iss: .init(value: teamId),
            iat: .init(value: Date()),
            exp: .init(value: Date().addingTimeInterval(5 * 60)),
            aud: .init(value: audience),
            sub: .init(value: bundleId)
        )
        return try await keys.sign(claims, kid: kid)
    }

    /// Exchanges the one-time authorization code for a refresh token. Best effort: returns nil on any failure.
    static func refreshToken(forAuthorizationCode code: String, client: any Client, logger: Logger) async -> String? {
        guard AppleConfig.canTalkToApple, let bundleId = AppleConfig.bundleId else {
            logger.warning("APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY not set: the Apple link can't be revoked on account deletion.")
            return nil
        }

        do {
            let secret = try await clientSecret()
            let response = try await client.post(URI(string: "\(audience)/auth/token")) { request in
                try request.content.encode(
                    AppleTokenRequest(client_id: bundleId, client_secret: secret, code: code, grant_type: "authorization_code"),
                    as: .urlEncodedForm
                )
            }
            guard response.status == .ok else {
                logger.error("Apple token exchange failed: \(response.status.code)")
                return nil
            }
            return try response.content.decode(AppleTokenResponse.self).refresh_token
        } catch {
            logger.error("Apple token exchange failed: \(error)")
            return nil
        }
    }

    /// Tells Apple the user no longer uses the app. Best effort: a failure is logged, and the
    /// account deletion goes on (the user asked for it).
    static func revoke(refreshToken: String, client: any Client, logger: Logger) async {
        guard AppleConfig.canTalkToApple, let bundleId = AppleConfig.bundleId else {
            logger.warning("Can't revoke the Apple link: APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY are not set.")
            return
        }

        do {
            let secret = try await clientSecret()
            let response = try await client.post(URI(string: "\(audience)/auth/revoke")) { request in
                try request.content.encode(
                    AppleRevokeRequest(client_id: bundleId, client_secret: secret, token: refreshToken, token_type_hint: "refresh_token"),
                    as: .urlEncodedForm
                )
            }
            if response.status != .ok {
                logger.error("Apple revoke failed: \(response.status.code)")
            }
        } catch {
            logger.error("Apple revoke failed: \(error)")
        }
    }
}
