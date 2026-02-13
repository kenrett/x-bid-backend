# Authentication and Session Lifecycle

This document describes the auth/session contract currently implemented by the backend runtime.

## Runtime Contract (Current)

- HTTP API auth is cookie-first through a signed HttpOnly `bs_session_id` cookie.
- `SessionToken` rows are the source of truth for session validity (active, revoked, expired).
- Login/signup/refresh responses still include `access_token` and `refresh_token` for compatibility clients.
- Bearer auth is fallback-only and can be disabled in production with `DISABLE_BEARER_AUTH=true`.
- ActionCable currently authenticates from the signed `bs_session_id` cookie.

## Session Lifecycle

### 1. Session creation (`POST /api/v1/login`, `POST /api/v1/signup`, `POST /api/v1/users`)

On successful auth or registration, backend runtime:

- Creates a `SessionToken` row.
- Issues a raw refresh token (stored hashed in `session_tokens.token_digest`).
- Returns JSON payload with `access_token`, `refresh_token`, `session_token_id`, and `user`.
- Sets two signed HttpOnly cookies:
  - `bs_session_id` (browser/API cookie)
  - `cable_session` (path `/cable`)
- Sets `X-Auth-Mode: cookie` response header.

### 2. Authenticated HTTP requests

`Auth::AuthenticateRequest.call(request)` resolves auth in this order:

1. Signed cookie (`bs_session_id`) via `Auth::CookieSessionAuthenticator`.
2. Bearer token fallback (`Authorization: Bearer ...`) via `Auth::BearerAuthenticator`, when allowed.

If bearer fallback is used, backend adds `X-Auth-Deprecation: bearer` to response headers.

### 3. Session refresh (`POST /api/v1/session/refresh`)

`/session/refresh` is available for clients that hold a refresh token.

- Accepts `refresh_token` (flat or nested under `session`).
- Revokes the old `SessionToken`.
- Creates a new `SessionToken` + refresh token pair.
- Re-issues session cookies (`bs_session_id`, `cable_session`).
- Returns the same auth response shape as login.

Note: This endpoint is part of the backend contract, but browser clients running cookie-first auth do not need to call it on every page load.

### 4. Logout (`DELETE /api/v1/logout`)

- Requires an authenticated session.
- Revokes the current `SessionToken`.
- Broadcasts session invalidation.
- Clears both session cookies server-side.

Logout is not client-only state clearing.

### 5. Session status endpoints

- `GET /api/v1/logged_in`: returns session/user context when session is valid.
- `GET /api/v1/session/remaining`: returns TTL metadata from active session token.

Both use the same cookie-first authentication path above.

## CSRF Contract (Cookie Auth)

For unsafe requests (`POST/PUT/PATCH/DELETE`) in browser cookie/origin contexts, unless request auth resolves via bearer:

1. Call `GET /api/v1/csrf` to receive `{ csrf_token }` and signed `csrf_token` cookie.
2. Send `X-CSRF-Token` header with the returned token.
3. Backend verifies header token matches signed cookie.

No local storage token persistence is required for this flow.

## What This Document Explicitly Avoids

- No assumption that frontend persists auth in `localStorage`.
- No assumption that frontend must attach bearer tokens on every request.
- No assumption that ActionCable accepts query-param JWT auth.

## Code Pointers

### Backend

- `app/controllers/api/v1/sessions_controller.rb`
- `app/controllers/application_controller.rb`
- `app/services/auth/authenticate_request.rb`
- `app/services/auth/cookie_session_authenticator.rb`
- `app/channels/application_cable/connection.rb`
- `app/models/session_token.rb`

## TL;DR

Cookie-first auth (`bs_session_id`) is the runtime default.
`SessionToken` rows control authorization/revocation.
Bearer and refresh-token paths exist for compatibility, not as the primary browser-session mechanism.
