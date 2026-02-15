# Auth Session Contract

## Scope
Browser session lifecycle between storefront clients and backend API.

## Endpoints
- `GET /api/v1/csrf`
- `POST /api/v1/login`
- `POST /api/v1/logout`
- `GET /api/v1/logged_in`

## Invariants
1. Session cookies are host-only for the API host (no broad wildcard domain cookies).
2. `logged_in` reflects current authenticated session state.
3. Logout invalidates active session tokens and clears legacy migration cookies when present.
4. CORS responses must allow configured storefront origins with credentials.

## Failure Contract
- `401 Unauthorized` for unauthenticated access.
- `403 Forbidden` for CSRF or authorization failures.
- Error payloads are JSON with stable code/message shape.
