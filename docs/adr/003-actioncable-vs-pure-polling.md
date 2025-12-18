# ADR-003: ActionCable + Polling (Hybrid Real-Time)

## Status
✅ Accepted

## Context
X-Bid requires:
- real-time auction updates
- instant session invalidation
- correctness under unreliable networks

Pure WebSockets are fragile:
- proxies block them
- mobile networks drop them
- clients disconnect silently

## Decision
We use a **hybrid approach**:

- ActionCable for low-latency updates
- Polling as a correctness and safety fallback

The backend remains the source of truth.

## Alternatives Considered
- Pure polling (rejected: poor UX under active bidding)
- Pure WebSockets (rejected: unreliable for security guarantees)

## Consequences
- Slightly more complexity on the frontend
- Significantly better reliability
- No “stale session” or “zombie bidder” bugs

## Notes
See `docs/real-time.md`.
