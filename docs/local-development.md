# 🛠 Local Development

This document explains **how to run X-Bid locally**, covering:

- Setup steps
- ENV vars
- Stripe test mode
- ActionCable notes
- Common “gotchas”

The goal is fast onboarding: **time-to-first-bid matters**. A new contributor should be able to run the full stack and place a test bid quickly.

## 🎯 High-Level Goals

Local development should be:

- Easy to bootstrap
- Close enough to production to catch real issues
- Safe (no accidental production calls)
- Reliable for real-time and payments flows

## 🧰 Setup Steps

> Note: This doc describes the expected flow. Adjust command specifics to match the repo scripts you actually use.

### 1) Clone repos

- Backend repo: `x-bid-backend`
- Frontend repo: `x-bid-frontend`

### 2) Backend setup (Rails API)

From the backend repo:

1. Install Ruby and bundler (match `.ruby-version` / Gemfile)
2. Install dependencies:
   - `bundle install`
3. Setup database:
   - create DB
   - run migrations
   - seed data (if applicable)
4. Start the server:
   - `bin/rails server`

Backend should be reachable at something like:
- `http://localhost:3000`

### 3) Frontend setup (React + Vite)

From the frontend repo:

1. Install Node (match `.nvmrc` if present)
2. Install dependencies:
   - `npm install` or `pnpm install`
3. Start the dev server:
   - `npm run dev`

Frontend should be reachable at something like:
- `http://localhost:5173`

### 4) Confirm time-to-first-bid

Sanity check:
- You can sign in (or create a seed user)
- You can view auctions
- You can place a bid
- You can see the UI update (polling or ActionCable)

If any of these fail, check the “Gotchas” section below.

## 🔐 Environment Variables

X-Bid relies on environment variables for:
- auth secrets
- database connectivity
- Stripe integration
- frontend API routing
- ActionCable configuration

### Backend ENV vars (typical)

Expected examples (adjust to your implementation):

- `DATABASE_URL`
- `JWT_SECRET` (or equivalent signing secret)
- `RAILS_MASTER_KEY` (if credentials are used)
- `FRONTEND_ORIGIN` (CORS)
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PUBLISHABLE_KEY` (optional; often frontend-only)
- `ACTION_CABLE_ALLOWED_ORIGINS` (if configured separately)

**Recommended practice**
- Use a `.env` file locally (via dotenv) or your shell
- Never commit secrets
- Provide a `.env.example` in each repo

### Frontend ENV vars (typical)

Expected examples (adjust to your implementation):

- `VITE_API_BASE_URL` (e.g. `http://localhost:3000`)
- `VITE_WS_BASE_URL` (if your cable client needs it)
- `VITE_STRIPE_PUBLISHABLE_KEY` (test key only)

**Recommended practice**
- Keep frontend env vars prefixed with `VITE_`
- Avoid embedding any secret keys in frontend env vars

## 🧪 Stripe Test Mode

Local development should always use **Stripe test mode**.

### Keys
- Use Stripe **test** keys only:
  - `sk_test_...`
  - `pk_test_...`

### Test cards (examples)
- Use Stripe’s test card numbers (from Stripe docs)
- Never use real card data

### Webhooks locally
You have two common options:

#### Option A: Use Stripe CLI (recommended)
- Stripe CLI can forward webhook events to your local backend
- This gives the most realistic webhook behavior

Expected flow:
- run webhook listener/forwarder
- perform checkout in the frontend
- observe webhook hitting backend locally
- verify credits are granted idempotently

#### Option B: Simulate webhook payloads
- Useful for unit/integration tests
- Less realistic than CLI forwarding

## ⚡ ActionCable Notes (Real-Time)

Real-time is optional for basic browsing, but important for:
- auction updates during bidding
- session invalidation

### What to verify locally
- WebSocket connection establishes successfully
- Subscriptions are scoped correctly
- Session invalidation broadcasts are received (if implemented)
- Auction updates broadcast on successful bid placement

### Common issues
- CORS / allowed origins misconfigured
- Using `localhost` vs `127.0.0.1` mismatch between frontend and backend
- WebSocket URL incorrect (ws:// vs wss://)
- Cookies/session headers not sent (if relevant)
- Reverse proxy assumptions that don’t exist locally

## 🧩 Common Gotchas

### 1) CORS / origin mismatch
Symptoms:
- requests fail in browser, but work in curl
- preflight errors

Fix:
- ensure backend allows the frontend origin (`http://localhost:5173`)
- ensure credentials/header config matches your auth approach

### 2) Auth tokens not persisting
Symptoms:
- login works, but refresh logs you out
- API calls fail after navigation

Fix:
- confirm token storage (`localStorage`)
- confirm auth hydration (`AuthProvider`)
- confirm API client attaches `Authorization: Bearer <JWT>`

### 3) WebSocket connects but no events arrive
Symptoms:
- socket shows connected
- no auction updates or invalidation

Fix:
- confirm subscriptions are created after auth hydration
- confirm server broadcast path runs post-commit
- confirm client channel names match server

### 4) Stripe checkout succeeds but credits don’t appear
Symptoms:
- you see success redirect
- balance unchanged

Fix:
- ensure webhook is actually being delivered locally
- verify webhook signature secret
- verify idempotency rules aren’t skipping incorrectly
- check logs for webhook processing failures

### 5) Seeds create inconsistent state
Symptoms:
- login user exists but can’t bid
- auctions exist but are ended/inactive
- missing bid packs

Fix:
- ensure seeds create a usable happy-path environment:
  - active auctions
  - user with credits
  - bid packs available
- document which seed user to use

### 6) Race conditions show up in dev
Symptoms:
- intermittent failures placing bids
- price flickers
- end time extends inconsistently

Fix:
- ensure bid placement is using DB locking and retries
- confirm local DB is Postgres (not sqlite) if prod uses Postgres
- avoid disabling transactions in dev

## ✅ Local Dev Checklist

Before opening a PR, confirm:

- [ ] Backend boots and migrations run cleanly
- [ ] Frontend boots and can fetch auctions
- [ ] Login works and persists after refresh
- [ ] Bid placement succeeds
- [ ] Credits decrement (or consume) correctly
- [ ] Stripe test purchase grants credits (via webhook)
- [ ] Real-time updates work (or polling fallback behaves correctly)

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Authentication & Session Lifecycle
- Authorization
- Real-Time
- Concurrency
- Payments
- Credits

## 🧾 TL;DR

- Run backend + frontend locally
- Use test keys only
- Use Stripe CLI for webhook realism
- Expect ActionCable to be finicky; polling must keep things safe
- Optimize for time-to-first-bid and repeatable onboarding
