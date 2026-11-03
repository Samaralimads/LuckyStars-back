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
    guard
        let host = Environment.get("DB_HOST"),
        let username = Environment.get("DB_USERNAME"),
        let password = Environment.get("DB_PASSWORD"),
        let dbName = Environment.get("DB_NAME")
    else {
        fatalError("Missing required database environment variables.")
    }

    let port = Environment.get("DB_PORT").flatMap(Int.init(_:)) ?? MySQLConfiguration.ianaPortNumber

    app.databases.use(DatabaseConfigurationFactory.mysql(
        hostname: host,
        port: port,
        username: username,
        password: password,
        database: dbName
    ), as: .mysql)

    // MARK: - JWT
    guard let jwtSecret = Environment.get("JWT_SECRET") else {
        fatalError("Missing required JWT_SECRET environment variable.")
    }
    await app.jwt.keys.add(hmac: HMACKey(from: jwtSecret), digestAlgorithm: .sha256)

    // MARK: - Routes
    try routes(app)
}
