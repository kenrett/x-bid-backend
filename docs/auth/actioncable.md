# ActionCable Authentication

## Why cookie auth
Browsers cannot set custom headers for WebSocket connections, so we authenticate ActionCable using a short-lived, HttpOnly cookie scoped to `/cable`.

## Cookie details
- Name: `cable_session`
- Value: `SessionToken` primary key (signed)
- Path: `/cable`
- HttpOnly: `true`
- SameSite: `Lax`
- Secure: `true` in production
- TTL: aligns to `SessionToken#expires_at` (session token TTL)

The cookie is rotated on login/signup/refresh and cleared on logout or session revocation.

## Connection behavior
`ApplicationCable::Connection` reads `cable_session`, loads the `SessionToken`, verifies it is active and not expired, and sets `current_user` and `current_session_token`.

## Troubleshooting checklist
- Is the `cable_session` cookie present in the browser?
- Does the cookie include `Path=/cable` and `SameSite=Lax`?
- Is `Secure` missing in production?
- Is the domain correct for your FE/BE origin?
- Has the session token been revoked or expired?
