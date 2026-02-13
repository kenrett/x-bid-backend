# ActionCable Authentication

## Runtime behavior (current)

`ApplicationCable::Connection` authenticates WebSocket connections using the signed browser session cookie:

```ruby
session_token_id = Auth::CookieSessionAuthenticator.session_cookie_id_from_jar(cookies)
```

The connection is rejected when the cookie is missing, unknown, revoked, or expired.

The current connection path does not read JWTs from query params, subprotocols, or Authorization headers.

## Cookies issued by auth endpoints

Login/signup/refresh set:

- `__Host-bs_session_id` (signed, HttpOnly, host-only, default path)
- `cable_session` (signed, HttpOnly, path `/cable`)
- legacy `bs_session_id` is expired with `Domain=.biddersweet.app` during migration

Current ActionCable runtime authenticates with `__Host-bs_session_id` by default. Legacy `bs_session_id` is only accepted when `ALLOW_LEGACY_SESSION_COOKIE_AUTH=true` (migration window), and remains non-authoritative otherwise.
`cable_session` is still issued/cleared for compatibility and operational continuity.

## Environment and domain expectations

- WebSocket URL should point to the API host that issues session cookies (for example `wss://api.biddersweet.app/cable`).
- Browser session cookies are host-only (no `Domain` attribute).
- `CORS_ALLOWED_ORIGINS` / `FRONTEND_ORIGINS` must include storefront origins.

## Troubleshooting checklist

- Is `__Host-bs_session_id` present after login/signup?
- Is the cookie signed and not expired/revoked server-side?
- Is the ActionCable URL pointing at the API host?
- Are cookie attributes (`Secure`, `SameSite`, `Domain`) valid for the current environment?
