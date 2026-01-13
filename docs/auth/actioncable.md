# ActionCable Authentication

## Why cookie auth
Browsers cannot reliably set custom headers for WebSocket connections, so ActionCable accepts a JWT via query param (or subprotocol) and can fall back to a short-lived, HttpOnly cookie scoped to `/cable`.

## Cookie details
- Name: `cable_session` (cookie fallback)
- Value: `SessionToken` primary key (signed)
- Path: `/cable`
- HttpOnly: `true`
- SameSite: `Lax` (same-site subdomains still receive the cookie)
- Secure: `true` in production
- TTL: aligns to `SessionToken#expires_at` (session token TTL)

The cookie is rotated on login/signup/refresh and cleared on logout or session revocation.

## Connection behavior
`ApplicationCable::Connection` reads a JWT from `?token=...` (or subprotocol) as the primary path. If no token is provided, it falls back to the `cable_session` cookie. It loads the `SessionToken`, verifies it is active and not expired, and sets `current_user` and `current_session_token`.

## Option A: single shared Cable host
Storefronts must always connect WebSocket to the API host (`API_HOST`), not the storefront subdomain.
The cookie is host-only and scoped to `/cable`, so it is only sent to the host that set it.

Recommended:
- `ACTION_CABLE_URL` points at the API host, e.g. `wss://api.biddersweet.app/cable`
- Frontend uses that API host for ActionCable, regardless of storefront subdomain
- `CORS_ALLOWED_ORIGINS` lists storefront origins (comma-separated)

## Troubleshooting checklist
- Is the `cable_session` cookie present in the browser?
- Does the cookie include `Path=/cable` and `SameSite=Lax`?
- Is `Secure` missing in production?
- Is the ActionCable URL pointing to the API host?
- Is the `token` query param present for the WebSocket connection?
- Has the session token been revoked or expired?
