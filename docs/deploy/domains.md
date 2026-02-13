# Domain Topology (Backend)

This backend serves the API at `api.biddersweet.app` and issues host-only browser session cookies bound to the API host.

## Required topology

- Storefronts live under `.biddersweet.app` (e.g., `biddersweet.app`, `www.biddersweet.app`, `afterdark.biddersweet.app`, `marketplace.biddersweet.app`, `account.biddersweet.app`).
- The API lives at `api.biddersweet.app`.

## Why this is required

- **Host-only browser session cookie:** Auth/session cookie is set as `__Host-bs_session_id` without a `Domain` attribute so sibling subdomains cannot receive it.
- **ActionCable cookie auth:** WebSocket auth reads `__Host-bs_session_id` by default; legacy `bs_session_id` fallback is enabled only when `ALLOW_LEGACY_SESSION_COOKIE_AUTH=true` during migration. `cable_session` is also issued on `/cable` for compatibility.
- **CORS with credentials:** We allow credentialed requests only from explicit storefront origins so browsers can attach cookies without CORS failures.

## Operational notes

- Production browser session cookies are `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`, and host-only (no `Domain`).
- Login/refresh/logout explicitly expire legacy `bs_session_id` using `Domain=.biddersweet.app` during the migration window.
