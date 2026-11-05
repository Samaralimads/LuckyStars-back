//
//  RateLimiter.swift
//  LuckyStarsBack
//
//  A small in-memory rate limiter for the routes attackers like to hammer
//  (login, register, password reset, pairing codes).
//
//  It lives in this process only: if the API ever runs as several instances,
//  each one counts on its own and a shared store (Redis, ...) is needed.
//

import Vapor

actor RateLimiter {
    static let shared = RateLimiter()

    private var hits: [String: [Date]] = [:]
    private let longestWindow: TimeInterval = 60 * 60

    /// Records one attempt for `key`.
    /// Returns nil when it is allowed, or the number of seconds to wait when the limit is reached.
    func hit(key: String, limit: Int, window: TimeInterval) -> Int? {
        let now = Date()
        var recent = (hits[key] ?? []).filter { now.timeIntervalSince($0) < window }

        if recent.count >= limit {
            hits[key] = recent
            let oldest = recent.first ?? now
            return max(1, Int((window - now.timeIntervalSince(oldest)).rounded(.up)))
        }

        recent.append(now)
        hits[key] = recent
        pruneIfNeeded(now: now)
        return nil
    }

    func reset() {
        hits.removeAll()
    }

    /// Keeps memory bounded: forget keys that haven't been seen for longer than any window.
    private func pruneIfNeeded(now: Date) {
        guard hits.count > 10_000 else { return }
        hits = hits.filter { _, dates in
            guard let last = dates.last else { return false }
            return now.timeIntervalSince(last) < longestWindow
        }
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    /// Names the limit, so login attempts don't use up the reset-password allowance.
    let scope: String
    let limit: Int
    let window: TimeInterval

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let key = "\(scope):\(Self.clientKey(for: request))"

        if let retryAfter = await RateLimiter.shared.hit(key: key, limit: limit, window: window) {
            var headers = HTTPHeaders()
            headers.add(name: "Retry-After", value: String(retryAfter))
            throw Abort(.tooManyRequests, headers: headers, reason: "Too many attempts. Please try again in a few minutes.")
        }

        return try await next.respond(to: request)
    }

    /// Signed-in users are counted per account, everyone else per IP address.
    /// Set TRUST_PROXY=true only behind a reverse proxy that sets X-Forwarded-For itself.
    static func clientKey(for request: Request) -> String {
        if let payload = request.auth.get(UserPayload.self) {
            return "user:\(payload.userId)"
        }
        if Environment.get("TRUST_PROXY") == "true",
           let forwarded = request.headers.first(name: "X-Forwarded-For"),
           let first = forwarded.split(separator: ",").first {
            return "ip:\(first.trimmingCharacters(in: .whitespaces))"
        }
        return "ip:\(request.remoteAddress?.ipAddress ?? "unknown")"
    }
}
