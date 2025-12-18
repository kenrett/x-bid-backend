# ADR-002: Command / Query Separation

## Status
✅ Accepted

## Context
As business logic grew, logic began leaking into:
- controllers
- models
- callbacks

This made behavior hard to reason about and test.

## Decision
We explicitly separate reads and writes:

- **Commands** perform state changes and side effects
- **Queries** read and shape data only

Controllers route intent; models remain thin.

## Alternatives Considered
- Fat models (rejected: hidden side effects)
- Service objects without separation (rejected: blurry responsibilities)
- CQRS with separate read DB (overkill)

## Consequences
- Clear homes for logic
- Predictable testing strategy
- Slightly more files, much more clarity
- Easier onboarding for new engineers

## Notes
See `docs/commands-and-queries.md`.
