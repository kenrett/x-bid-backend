# 🚀 Deployment

This document explains **how X-Bid is deployed and operated**, covering:

- Render/Vercel flow
- ENV separation
- Database resets (and when allowed)
- Background jobs
- Rollback strategy

The goal is to make production **boring, predictable, and recoverable**.

## 🎯 High-Level Goals

Deployment should be:

- Reproducible (same steps every time)
- Safe (clear separation between environments)
- Observable (easy to diagnose issues quickly)
- Recoverable (rollbacks are straightforward)
- Explicit (no mystery state changes)

## 🧭 Render / Vercel Flow

X-Bid is deployed as two primary components:

### Backend (Render)
Render hosts:
- Rails API
- PostgreSQL database
- Background workers (if configured)
- ActionCable (WebSocket) support

Typical flow:
1. Push to backend repo main branch (or release branch)
2. Render builds the app (bundle install, assets if any)
3. Render runs migrations (if configured)
4. Render deploys the new web service revision
5. Workers (if present) deploy alongside

### Frontend (Vercel)
Vercel hosts:
- React/Vite static build
- Edge delivery / caching
- Environment variable config for API base URL

Typical flow:
1. Push to frontend repo main branch (or release branch)
2. Vercel builds the app (install deps, `vite build`)
3. Vercel deploys to production domain

## 🔐 ENV Separation

X-Bid must maintain strict separation across:

- `development` (local)
- `staging` (optional but recommended)
- `production`

### Non-negotiable rules
- Production secrets never exist in dev/staging
- Test Stripe keys must never exist in production
- Production Stripe keys must never exist in dev
- Production DB must never be pointed to by dev frontend

### Backend ENV vars (typical categories)
- Auth secrets (JWT signing, rails secret key base)
- Database credentials / `DATABASE_URL`
- CORS allowed origins
- Stripe secrets (live vs test)
- Webhook signing secret (live vs test)
- ActionCable allowed origins
- Logging / monitoring config

### Frontend ENV vars (typical categories)
- API base URL (staging vs prod)
- WebSocket base URL (if needed)
- Stripe publishable key (live vs test)

**Recommended practice**
- Maintain `.env.example` (local only)
- Maintain a documented list of required production env vars
- Fail fast on boot if required env vars are missing

## 🗄 Database Resets (and When Allowed)

Database resets are a sharp tool. Treat them as such.

### ✅ Allowed
- Local development DB resets at will
- Staging DB resets if staging is non-critical and explicitly disposable
- A brand-new production environment before real users/data exist (rare)

### ❌ Not allowed (without explicit “we accept data loss” decision)
- Resetting production DB once real users or payments exist
- Any reset that could invalidate financial records or audit trails

### Preferred alternatives to prod reset
If production is “broken”:
- Run a migration fix
- Backfill missing data safely
- Add reconciliation jobs
- Use admin tooling to correct state
- Restore from backup (if catastrophic)

**Rule**
> Once money touches the system, production resets must be treated as an incident-level action.

## 🧵 Background Jobs

Background jobs should run in a separate worker process (or processes), not inside the web dyno.

### What jobs are typically responsible for
- Auction close and settlement workflows
- Retry windows / expiry
- Payment reconciliation
- Cleanup tasks
- Email/notification dispatch (if present)

### Operational expectations
- Jobs must be idempotent
- Jobs must re-check state before mutating
- Job failures should be logged with high signal
- Retried jobs must not double-apply side effects (credits, state transitions)

### Deployment considerations
- Render should deploy web + worker together when possible
- Migrations that change job behavior should be backward compatible across deploy boundaries
- If you change job queues or schedules, document it here

## 🔁 Rollback Strategy

Rollbacks are part of normal operations. Plan for them.

### Frontend rollback (Vercel)
- Roll back by promoting a previous deployment
- Because frontend is static, rollbacks are typically fast and safe
- Ensure the frontend is compatible with the backend API during rollback windows

### Backend rollback (Render)
- Roll back by reverting to a previous Render deploy/revision
- Be careful with migrations:
  - rolling back code is easy
  - rolling back schema is hard

## 🧬 Migration Strategy (Rollback-Safe)

To keep rollbacks safe:

### Prefer backward-compatible migrations
- Add columns first (nullable)
- Deploy code that can handle both old/new schema
- Backfill in a job or migration
- Then enforce constraints / remove old columns later

### Avoid destructive migrations in a single deploy
- Dropping columns
- Renaming without compatibility layer
- Changing enums without safe mapping
- Altering constraints that can lock large tables unexpectedly

**Rule**
> Migrations should be survivable across a deploy window where old and new code may overlap.

## 🧯 Deployment Failure Recovery

### If backend deploy fails
- Check build logs and migration logs
- If migrations applied but code failed, deploy a hotfix or rollback carefully
- If traffic is impacted, prioritize restoring a working API first

### If frontend deploy fails
- Promote last known good deployment
- Fix build errors on mainline
- Ensure environment variables are correct

### If Stripe webhooks break
- Confirm webhook signing secret matches environment
- Confirm endpoint is reachable and returns 2xx for valid events
- Confirm idempotency prevents re-processing explosions
- Reconcile missed events if needed (manual or automated)

## ✅ Release Checklist (Recommended)

Before deploying:

- [ ] Required env vars set for target environment
- [ ] Migrations reviewed for backward compatibility
- [ ] Admin-only mutations still behind `Admin::*` commands
- [ ] Payments/webhooks tested in the correct Stripe mode (test vs live)
- [ ] ActionCable origin config verified (if changed)
- [ ] Smoke test plan ready (login, view auctions, place bid, purchase credits)
- [ ] Rollback path understood (which deploy to revert to)

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Local Development
- Payments
- Error Handling
- Real-Time
- Concurrency

## 🧾 TL;DR

- Backend deploys on Render, frontend deploys on Vercel
- Environments must be strictly separated
- Production DB resets are basically forbidden once real data exists
- Background jobs must be idempotent and deployable safely
- Rollbacks are expected; schema changes must be rollback-aware
