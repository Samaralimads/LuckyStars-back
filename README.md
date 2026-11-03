# LuckyStarsBack

RESTful API for **Lucky Stars**, an iOS app that helps couples find and plan activities to do together.
This backend handles user accounts, partner pairing, the activity catalog, proposing/responding to
planned activities, important dates, and password reset.

## Tech stack

- **[Vapor](https://vapor.codes)** 4 — server-side Swift framework
- **Fluent** + **FluentMySQLDriver** — ORM on top of **MySQL**
- **JWT** (`vapor/jwt`) — token-based authentication
- **SwiftNIO** / **SQLKit** — a few manual SQL queries where Fluent alone isn't enough
- Swift 6 (strict concurrency enabled via `ExistentialAny`)

## Project structure

```
Sources/LuckyStarsBack/
├── Auth/                 JWTMiddleware, UserPayload
├── Controllers/          one route collection per resource (User, Couple, Activity, PlannedActivity, ImportantDate, Favorite, PasswordReset)
├── DTOs/                 request/response JSON shapes (decoupled from Fluent models)
├── Enums/                BookingStatus, Budget
├── Models/               Fluent entities (User, Couple, Invitation, Activity, Category, PlannedActivity, FavoriteActivity, ImportantDate, PasswordReset)
├── configure.swift       CORS, database connection, JWT key, route registration
├── routes.swift          registers each RouteCollection
└── entrypoint.swift
```

## Requirements

- Swift 6 / a recent Xcode with the matching toolchain
- A reachable MySQL server (local or remote)

## Configuration

The project reads its configuration from environment variables (see `configure.swift`):

| Variable         | Purpose                                              | Required |
|------------------|--------------------------------------------------------|:--------:|
| `DB_HOST`        | MySQL host                                              | ✅ |
| `DB_PORT`        | MySQL port (defaults to the standard MySQL port)        | – |
| `DB_USERNAME`    | MySQL user                                              | ✅ |
| `DB_PASSWORD`    | MySQL password                                          | ✅ |
| `DB_NAME`        | Database name                                           | ✅ |
| `JWT_SECRET`     | HMAC (SHA-256) secret used to sign/verify JWTs          | ✅ |
| `BREVO_API_KEY`  | Brevo API key, used to send password-reset emails       | for `PasswordResetController` |
| `BREVO_SENDER`   | Sender address for password-reset emails                | for `PasswordResetController` |

⚠️ There are no Fluent migrations in this project: the database schema has to be created manually
(from the MPD SQL script — see the project's MERISE design) before starting the server. The Fluent
models in `Models/` must stay in sync with that schema.

## Running the project

```bash
swift build      # build
swift run        # start the server (http://127.0.0.1:8080 by default)
swift test       # run tests
```

## Routes overview

| Resource | Method & path | Protected (JWT) |
|---|---|:---:|
| **Users** | `POST /users/register` | |
| | `POST /users/login` | |
| | `GET /users/me` | ✅ |
| | `PUT /users/me` | ✅ |
| | `PUT /users/me/password` | ✅ |
| | `DELETE /users/me` | ✅ |
| **Couples** | `GET /couples/me/invitation` | ✅ |
| | `POST /couples/create` | ✅ |
| | `POST /couples/join` | ✅ |
| | `GET /couples/me` | ✅ |
| **Activities** | `GET /activities` | |
| | `GET /activities/:activityId` | |
| | `GET /categories` | |
| **Planned activities** | `POST /planned-activities` | ✅ |
| | `GET /planned-activities/couple` | ✅ |
| | `PUT /planned-activities/:id/accept` | ✅ |
| | `PUT /planned-activities/:id/decline` | ✅ |
| | `PUT /planned-activities/:id/reschedule` | ✅ |
| **Important dates** | `GET /important-dates` | ✅ |
| | `POST /important-dates` | ✅ |
| | `PUT /important-dates/:id` | ✅ |
| | `DELETE /important-dates/:id` | ✅ |
| **Favorites** | `GET /favorites` | ✅ |
| | `POST /favorites/:activityId` | ✅ |
| | `DELETE /favorites/:activityId` | ✅ |
| **Password reset** | `POST /auth/forgot-password` | |
| | `POST /auth/verify-code` | |
| | `POST /auth/reset-password` | |

Protected routes expect an `Authorization: Bearer <token>` header, obtained via `POST /users/login`.
