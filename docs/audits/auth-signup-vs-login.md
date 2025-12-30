# Auth Audit: Signup vs Login (SessionToken Revocation)

## TL;DR

- Canonical auth design is **SessionToken-backed**: JWT contains `session_token_id`, and the API verifies it by looking up a `SessionToken` row.
- `POST /api/v1/login` follows this design and is **server-revocable**.
- **Legacy registration** `POST /api/v1/users` mints a JWT without `session_token_id` and creates **no** `SessionToken` row, so:
  - It is **not revocable server-side** (no server session row exists to revoke).
  - It is also **not usable** for endpoints guarded by `authenticate_request!` (they require `session_token_id`).
- `POST /api/v1/signup` (new) follows the login contract and **is revocable**.

## Canonical Login / Session Creation Path

### Route + controller

- Route: `POST /api/v1/login` (`config/routes.rb:28`)
- Handler: `Api::V1::SessionsController#create` (`app/controllers/api/v1/sessions_controller.rb:18`)

### SessionToken creation

- `SessionToken.generate_for(user:)` creates a persisted `SessionToken` row and returns `[session_token, raw_token]` (`app/models/session_token.rb:16`)
- Login calls it here: `app/controllers/api/v1/sessions_controller.rb:25`

### JWT contains `session_token_id`

- Login response is built in `build_session_response` (`app/controllers/api/v1/sessions_controller.rb:106`)
- The JWT payload includes `session_token_id` (`app/controllers/api/v1/sessions_controller.rb:107`)
- The JWT is minted via `encode_jwt(..., expires_at: session_token.expires_at)` (`app/controllers/api/v1/sessions_controller.rb:115`)

### Server-side revocation enforcement

- `authenticate_request!` decodes JWT then loads `SessionToken` by `session_token_id` (`app/controllers/application_controller.rb:14` to `app/controllers/application_controller.rb:16`)
- If the session token is revoked/expired, request is rejected (`app/controllers/application_controller.rb:16` to `app/controllers/application_controller.rb:18`)

**Conclusion for login:** server-side revocation works (revoke session token row, JWT becomes invalid on next request).

## Signup / Registration Paths

There are currently two registration-ish endpoints:

### A) Legacy registration: `POST /api/v1/users` (bypasses SessionToken)

- Route: `POST /api/v1/users` (`config/routes.rb:25`)
- Handler: `Api::V1::UsersController#create` (`app/controllers/api/v1/users_controller.rb:7`)

Behavior:
- Creates a `User` (`app/controllers/api/v1/users_controller.rb:8`)
- Mints a JWT using only `user_id`: `encode_jwt(user_id: user.id)` (`app/controllers/api/v1/users_controller.rb:10`)
- Returns `{ token, user }` (`app/controllers/api/v1/users_controller.rb:12`)
- **Does not** call `SessionToken.generate_for` and does **not** persist a `SessionToken` row.

Impact:
- **Revocation works?** **No** (there is no server-side session row to revoke; JWT is self-contained).
- **Usable with `authenticate_request!`?** **No** (JWT has no `session_token_id`, and auth lookup is session-token based).

### B) Session-based signup: `POST /api/v1/signup` (aligned with login)

- Route: `POST /api/v1/signup` (`config/routes.rb:26`)
- Handler: `Api::V1::RegistrationsController#create` (`app/controllers/api/v1/registrations_controller.rb:6`)

Behavior:
- Creates a `User`
- Calls `SessionToken.generate_for` and returns the login-equivalent response contract (token + refresh_token + session metadata).

Impact:
- **Revocation works?** **Yes** (session row exists; `authenticate_request!` enforces it).

## Side-by-side comparison

| Flow | Endpoint | JWT includes `session_token_id`? | Creates `SessionToken` row? | Server-side revocation works? |
|---|---|---:|---:|---:|
| Login | `POST /api/v1/login` | Yes | Yes | Yes |
| Signup (legacy) | `POST /api/v1/users` | No | No | No |
| Signup (session-based) | `POST /api/v1/signup` | Yes | Yes | Yes |

## Conclusion (bypass?)

**Yes (for `POST /api/v1/users`):** legacy signup currently mints a JWT without a `SessionToken` row, which bypasses the server-revocable SessionToken-based auth design.

If clients use **`POST /api/v1/signup`** (session-based), that bypass does not occur.

