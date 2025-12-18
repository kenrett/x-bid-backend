# ADR-004: Pessimistic Locking for Bids

## Status
✅ Accepted

## Context
Auction bidding is a high-contention write path.
Multiple users may attempt to:
- place bids
- update price
- extend end time
simultaneously.

Optimistic locking risks:
- repeated retries
- inconsistent state
- complex conflict resolution

## Decision
We use **pessimistic database locking** on the auction row during bid placement.

All bid validation, mutation, and extension logic runs under the same lock.

## Alternatives Considered
- Optimistic locking (rejected: high contention)
- Application-level mutexes (rejected: unsafe across processes)
- Queue-based bidding (rejected: latency + complexity)

## Consequences
- Serialized bid processing (intentional)
- Deterministic outcomes
- Safer extension window logic
- Predictable retry behavior

## Notes
See `docs/concurrency.md` for full walkthroughs.
