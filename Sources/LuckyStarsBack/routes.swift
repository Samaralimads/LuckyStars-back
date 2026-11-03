import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        "Lucky Stars API is running."
    }

    try app.register(collection: UserController())
    try app.register(collection: CoupleController())
    try app.register(collection: ActivityController())
    try app.register(collection: PlannedActivityController())
    try app.register(collection: ImportantDateController())
    try app.register(collection: FavoriteController())
    try app.register(collection: PasswordResetController())

}
