import NIOSSL
import Fluent
import FluentMySQLDriver
import Vapor
import JWT

public func configure(_ app: Application) async throws {

    // MARK: - CORS
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.contentType, .authorization]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig))

    // MARK: - Database
    // Tests read TEST_DB_* instead of DB_*, so a test run can never reach the real database.
    let prefix = app.environment == .testing ? "TEST_DB_" : "DB_"
    guard
        let host = Environment.get("\(prefix)HOST"),
        let username = Environment.get("\(prefix)USERNAME"),
        let password = Environment.get("\(prefix)PASSWORD"),
        let dbName = Environment.get("\(prefix)NAME")
    else {
        fatalError("Missing required database environment variables (\(prefix)HOST, \(prefix)USERNAME, \(prefix)PASSWORD, \(prefix)NAME).")
    }

    let port = Environment.get("\(prefix)PORT").flatMap(Int.init(_:)) ?? MySQLConfiguration.ianaPortNumber

    app.databases.use(DatabaseConfigurationFactory.mysql(
        hostname: host,
        port: port,
        username: username,
        password: password,
        database: dbName
    ), as: .mysql)

    // MARK: - JWT
    guard let jwtSecret = Environment.get("JWT_SECRET") ?? (app.environment == .testing ? "test-only-secret" : nil) else {
        fatalError("Missing required JWT_SECRET environment variable.")
    }
    await app.jwt.keys.add(hmac: HMACKey(from: jwtSecret), digestAlgorithm: .sha256)

    if Environment.get("BREVO_API_KEY") == nil || Environment.get("BREVO_SENDER") == nil {
        app.logger.warning("BREVO_API_KEY / BREVO_SENDER not set: password reset emails will not be sent.")
    }

    // MARK: - Routes
    try routes(app)
}
