# Domain Topology (Backend)

This backend serves the API at `api.biddersweet.app` and issues cookie-based sessions that must be shared across storefront subdomains.

## Required topology

- Storefronts live under `.biddersweet.app` (e.g., `biddersweet.app`, `www.biddersweet.app`, `afterdark.biddersweet.app`, `marketplace.biddersweet.app`, `account.biddersweet.app`).
- The API lives at `api.biddersweet.app`.

## Why this is required

- **Cookie sharing across subdomains:** Auth/session cookies are set with `domain=.biddersweet.app` in production so the browser sends them to `api.biddersweet.app` from all storefronts.
- **ActionCable cookie auth:** WebSocket auth currently reads `bs_session_id`; `cable_session` is also issued on `/cable` for compatibility.
- **CORS with credentials:** We allow credentialed requests only from explicit storefront origins so browsers can attach cookies without CORS failures.

## Operational notes

- Production cookies are `Secure`, `HttpOnly`, `SameSite=Lax`, and scoped to `domain=.biddersweet.app`.
- Logout/revocation clears cookies using the same `domain`, `path`, `SameSite`, and `Secure` attributes to ensure browsers remove them.
- If cross-site requests require `SameSite=None`, set `SESSION_COOKIE_SAMESITE=none` and `ALLOW_SAMESITE_NONE=true` explicitly.
