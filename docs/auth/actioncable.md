# ActionCable Authentication

## Runtime behavior (current)

`ApplicationCable::Connection` authenticates WebSocket connections using the signed browser session cookie:

```ruby
Auth::CookieSessionAuthenticator::COOKIE_NAMES.each do |cookie_name|
  session_token_id = cookies.signed[cookie_name]
  break if session_token_id.present?
end
```

The connection is rejected when the cookie is missing, unknown, revoked, or expired.

The current connection path does not read JWTs from query params, subprotocols, or Authorization headers.

## Cookies issued by auth endpoints

Login/signup/refresh set:

- `__Host-bs_session_id` (signed, HttpOnly, host-only, default path)
- `cable_session` (signed, HttpOnly, path `/cable`)
- legacy `bs_session_id` is expired with `Domain=.biddersweet.app` during migration

Current ActionCable runtime authenticates with `__Host-bs_session_id` and falls back to legacy `bs_session_id` during migration.
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
