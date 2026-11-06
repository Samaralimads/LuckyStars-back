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
├── routes.swift          registers each RouteCollection
└── entrypoint.swift
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
| | `PUT /couples/me` (change the anniversary date) | ✅ |
| | `DELETE /couples/me` (unpair) | ✅ |
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
| **Sign in with Apple** | `POST /auth/apple` | |
| **Password reset** | `POST /auth/forgot-password` | |
| | `POST /auth/verify-code` | |
| | `POST /auth/reset-password` | |

Protected routes expect an `Authorization: Bearer <token>` header, obtained via `POST /users/login`.
