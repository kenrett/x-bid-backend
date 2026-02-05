# AGENTS.md - x-bid-backend

## Scope
This repository is the Rails API/backend for X-Bid.

Primary responsibilities:
- Auth/session lifecycle
- Auctions, bids, wallets, payments, admin workflows
- API contracts consumed by `x-bid-frontend`
- Operational readiness for Render deployments

## Deployment Target
- Backend deploy platform: **Render**
- Frontend deploy platform: **Vercel** (separate repo)
- Treat cross-repo API compatibility as a hard requirement.

## Non-Negotiables
- Do not commit or expose secrets (`config/master.key`, `.env*`, credentials files, tokens).
- Preserve money correctness and idempotency on checkout/payment/refund flows.
- Enforce authn/authz boundaries (user/admin/superadmin) on every changed endpoint.
- Prefer explicit, stable error payloads and HTTP status codes.
- Avoid destructive data operations unless explicitly requested.

## Required Workflow For Changes
1. Understand the full vertical slice (request -> service/command -> DB -> response/events).
2. Update backend code and tests together.
3. Verify OpenAPI contract is current:
   - `bundle exec rails openapi:generate`
4. Run quality checks before handoff:
   - `bin/test`
   - `bin/lint`
5. Note any required frontend follow-ups if contract changes.

## Architecture Expectations
- Keep controllers thin; business logic belongs in services/commands.
- Return `ServiceResult` consistently for service outcomes.
- Keep read concerns in queries/read models where applicable.
- Use explicit transactions/locking for concurrency-sensitive flows (bidding, credits).
- Publish domain events where existing patterns expect them.

## Render Readiness Checklist
- Migrations are safe to run during deploy.
- Required env vars are documented and present (`DATABASE_URL`, `SECRET_KEY_BASE`, Stripe keys, etc.).
- Health endpoints remain valid (`/up`, `/api/v1/health`, cable health).
- Background/queue behavior is accounted for in deployment changes.
- Logging/error messages are actionable for production debugging.

## Frontend Contract Guardrails
- If response/request shape changes, regenerate OpenAPI and call it out.
- Keep pagination and envelope patterns consistent.
- Avoid silent schema drift; prefer additive changes when possible.
- Coordinate breaking changes with `x-bid-frontend` before merge.

## PR Handoff Template
- What changed:
- Risk level:
- Migration/data impact:
- API contract impact:
- Render deploy notes:
- Manual verification performed:
