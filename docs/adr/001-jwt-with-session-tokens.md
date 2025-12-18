# ADR-001: JWTs Backed by Session Tokens

## Status
✅ Accepted

## Context
Pure JWT-based authentication makes immediate server-side revocation difficult.
X-Bid requires:
- forced logout when a user is disabled
- admin-initiated invalidation
- real-time session revocation
- auditability of active sessions

## Decision
We use short-lived JWTs that reference a persisted `SessionToken` record.

- JWTs authenticate requests
- SessionToken rows authorize session validity
- Backend checks session validity on every request
- Sessions can be revoked instantly by invalidating the DB row

## Alternatives Considered
- Pure JWT (rejected: no server-side revocation)
- Server-only session cookies (rejected: poor API ergonomics)
- OAuth-style access/refresh token pairs (overkill for current scope)

## Consequences
- Slightly more complexity than pure JWT
- Strong security guarantees
- Real-time invalidation is possible
- Sessions are auditable and observable

## Notes
See `docs/auth.md` for full lifecycle details.
