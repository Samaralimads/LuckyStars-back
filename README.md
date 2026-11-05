# LuckyStarsBack

RESTful API for **Lucky Stars**, an iOS app that helps couples find and plan activities to do together.
This backend handles user accounts, partner pairing, the activity catalog, proposing/responding to
planned activities, important dates, and password reset.

## Tech stack

- **[Vapor](https://vapor.codes)** 4 — server-side Swift framework
- **Fluent** + **FluentMySQLDriver** — ORM on top of **MariaDB / MySQL** (production runs MariaDB 10.4)
- **JWT** (`vapor/jwt`) — token-based authentication
- **SwiftNIO** / **SQLKit** — a few manual SQL queries where Fluent alone isn't enough
- Swift 6 (strict concurrency enabled via `ExistentialAny`)

## Project structure

```
Sources/LuckyStarsBack/
├── Auth/                 JWTMiddleware, UserPayload, RateLimiter (rate-limit middleware), Validation (input rules)
├── Controllers/          one route collection per resource (User, Couple, Activity, PlannedActivity, ImportantDate, Favorite, PasswordReset)
├── DTOs/                 request/response JSON shapes (decoupled from Fluent models)
├── Models/               Fluent entities (User, Couple, Invitation, Activity, Category, PlannedActivity, FavoriteActivity, ImportantDate, PasswordReset)
├── configure.swift       CORS, database connection, JWT key, route registration
Database/
├── schema.sql            the database structure (no data), for a new database
├── seed.sql              categories and activities
└── migrations/           numbered SQL files to bring an existing database up to date
├── routes.swift          registers each RouteCollection
└── entrypoint.swift
```

## Requirements

- Swift 6 / a recent Xcode with the matching toolchain
- A reachable MariaDB/MySQL server (local or remote), or Docker (see below)

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
| `TRUST_PROXY`    | `true` only behind a reverse proxy that sets `X-Forwarded-For` (used by the rate limits) | – |
| `LOG_LEVEL`      | `info` (default in Docker). `debug` also logs database queries and their values | – |

Without `BREVO_*` the server starts, but password reset emails are not sent (a warning is logged).

## Database

There are no Fluent migrations: the database is plain SQL, kept in `Database/`.
The Fluent models in `Models/` must stay in sync with it.

- **New database**: run `Database/schema.sql`, then `Database/seed.sql`. With Docker this happens
  automatically the first time (see below).
- **Existing database**: apply the files in `Database/migrations/` in order, once each, **after backing up**.
  Read the comment at the top of each file first. Run the migration, then deploy the matching backend.
- The pairing code (`invitation.invitation_code`, 6 digits) is created by a database trigger when a user
  registers. Pairing itself (`POST /couples/join`) is the stored procedure `create_couple_from_invitation`.
- Never commit a full database dump: it contains emails, password hashes and reset codes.

## Running the project

```bash
swift build      # build
swift run        # start the server (http://127.0.0.1:8080 by default)
swift test       # run tests
```

### With Docker (API + MariaDB)

```bash
cp .env.example .env     # then fill in DB_PASSWORD, JWT_SECRET (and BREVO_* for emails)
docker compose up --build
```

The database is only reachable from the API container (its port is not published).

### Tests

`swift test` needs a database. Use a **separate, empty test database**, never the real one: set
`TEST_DB_HOST`, `TEST_DB_USERNAME`, `TEST_DB_PASSWORD` and `TEST_DB_NAME` (the tests refuse to run
without them), and load `Database/schema.sql` into it first.

### HTTPS

The API itself speaks plain HTTP. Put a reverse proxy that terminates TLS in front of it, for example
[Caddy](https://caddyserver.com), which gets certificates by itself:

```
api.example.com {
    reverse_proxy app:8080
}
```

Then set `TRUST_PROXY=true`, and point the iOS app (`APIClient.swift`) at `https://api.example.com`.

## Security notes

- Rate limits (per IP, or per account when signed in; in memory, so per server instance): login 10 / 15 min,
  register 20 / hour, forgot-password 5 / 15 min, verify-code and reset-password 15 / 15 min,
  join couple 10 / 15 min.
- A password reset code locks after 5 wrong guesses; a new email can be requested once a minute.
- Login tokens last 30 days and stop working as soon as the account is deleted. There is no refresh or
  revocation yet.

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
| | `PUT /couples/me` (change the anniversary date) | ✅ |
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
