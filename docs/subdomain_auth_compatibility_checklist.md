# Subdomain auth compatibility checklist

## Current auth transport

- HTTP API auth is cookie-first via signed `__Host-bs_session_id` (`Auth::CookieSessionAuthenticator`); legacy `bs_session_id` fallback is only enabled when `ALLOW_LEGACY_SESSION_COOKIE_AUTH=true` during migration.
- Bearer auth (`Authorization: Bearer <jwt>`) is fallback-only (`Auth::BearerAuthenticator`) and can be disabled in production with `DISABLE_BEARER_AUTH=true`.
- WebSocket (`/cable`) auth reads signed browser session cookies in `ApplicationCable::Connection` through `Auth::CookieSessionAuthenticator` (`__Host-bs_session_id` by default, optional legacy fallback only when `ALLOW_LEGACY_SESSION_COOKIE_AUTH=true`).

## Required frontend origins

Ensure the frontend origin is one of:

- `https://biddersweet.app`
- `https://www.biddersweet.app`
- `https://afterdark.biddersweet.app`
- `https://marketplace.biddersweet.app`
- `https://account.biddersweet.app`

## CORS and CSRF requirements (cookie-first auth)

- `Access-Control-Allow-Credentials: true` must be present for allowed origins.
- Frontend requests must send credentials (`withCredentials` / `credentials: include`).
- For unsafe requests in browser cookie/origin contexts, include `X-CSRF-Token` from `GET /api/v1/csrf` unless auth resolves via bearer.
- If a compatibility client uses bearer auth, allow the `Authorization` request header.

## Cookie notes

- Browser session cookies are host-only (no `Domain` attribute).
- Session cookies should remain `Secure` + `HttpOnly` with explicit `SameSite` policy.
- WebSocket compatibility depends on storefront -> API host requests carrying session cookies.
