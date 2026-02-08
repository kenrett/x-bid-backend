# ActionCable Authentication

## Runtime behavior (current)

`ApplicationCable::Connection` authenticates WebSocket connections using the signed browser session cookie:

```ruby
session_token_id = cookies.signed[:bs_session_id]
session_token = SessionToken.find_by(id: session_token_id)
```

The connection is rejected when the cookie is missing, unknown, revoked, or expired.

The current connection path does not read JWTs from query params, subprotocols, or Authorization headers.

## Cookies issued by auth endpoints

Login/signup/refresh set:

- `bs_session_id` (signed, HttpOnly, default path)
- `cable_session` (signed, HttpOnly, path `/cable`)

Current ActionCable runtime authenticates with `bs_session_id`.
`cable_session` is still issued/cleared for compatibility and operational continuity.

## Environment and domain expectations

- WebSocket URL should point to the API host that issues session cookies (for example `wss://api.biddersweet.app/cable`).
- Production cookies are scoped to `.biddersweet.app` when host/domain rules match.
- `CORS_ALLOWED_ORIGINS` / `FRONTEND_ORIGINS` must include storefront origins.

## Troubleshooting checklist

- Is `bs_session_id` present after login/signup?
- Is the cookie signed and not expired/revoked server-side?
- Is the ActionCable URL pointing at the API host?
- Are cookie attributes (`Secure`, `SameSite`, `Domain`) valid for the current environment?
