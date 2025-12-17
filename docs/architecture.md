# 🧠 Architecture & Patterns

This document provides a **high-level architectural overview of X-Bid**, explaining how the major systems fit together and where responsibilities live.

Its goal is to let a **new senior engineer understand the system end-to-end in ~30 minutes**, without diving into implementation details prematurely.

## 🎯 High-Level Goals

This architecture is designed to:

- Keep **business logic explicit and discoverable**
- Enforce **clear domain and responsibility boundaries**
- Support **real-time, high-concurrency workflows**
- Scale safely as product complexity grows
- Avoid cargo-cult patterns and accidental coupling

## 🏗 System Overview

At a high level, X-Bid consists of:

- A **Rails API-only backend** that owns all state and business rules
- A **React + Vite frontend** that renders UI and manages client state
- A **real-time layer** for live updates and invalidation
- A **payments system** for monetization and credits
- **Background jobs** for async and time-based work
- A **cloud deployment** split across Render and Vercel

Each layer is intentionally simple on its own, with complexity pushed to explicit boundaries.

## 🧩 Backend (Rails API-only)

The backend is the **single source of truth**.

### Responsibilities

- Authentication and authorization
- Auction lifecycle and bidding logic
- Credit accounting and payments
- Concurrency control and locking
- Real-time event broadcasting
- Data persistence and integrity

### Key architectural choices

- API-only Rails app
- Explicit **Command vs Query** separation
- Admin vs Public domain boundaries
- Service objects for orchestration
- Models kept intentionally thin

Controllers:
- Authenticate requests
- Route intent
- Never contain business logic

## 🎨 Frontend (React + Vite)

The frontend is responsible for **presentation and client-side state**, not business rules.

### Responsibilities

- Rendering auction and bidding UI
- Managing client session state
- Connecting to real-time channels
- Polling for session validity
- Submitting user intent to the API

### Key architectural choices

- Vite for fast builds and local development
- Feature-based folder structure
- `AuthProvider` as the single auth source of truth
- API client abstraction for all requests
- Optimistic UI where safe, authoritative backend always wins

## ⚡ Real-Time Layer (ActionCable)

Real-time updates are used where **latency matters**.

### Responsibilities

- Auction state updates
- Bid placement broadcasts
- Session invalidation
- Admin-triggered state changes

### Design principles

- WebSockets complement polling, not replace it
- All real-time events originate from the backend
- Clients treat broadcasts as hints, not authority
- Authorization is enforced before broadcasting

## 💳 Payments (Stripe)

Payments are handled through **Stripe**, with strong idempotency guarantees.

### Responsibilities

- Checkout and purchase flows
- Webhook processing
- Credit granting
- Refunds and reconciliation

### Design principles

- Stripe is never trusted blindly
- Webhooks are idempotent
- Credits are granted via explicit domain logic
- Money-related mutations are admin-guarded

## 🕒 Background Jobs

Background jobs handle **work that must not block requests**.

### Responsibilities

- Auction close and settlement
- Retry windows and extensions
- Payment reconciliation
- Cleanup and expiry jobs

### Design principles

- Jobs are idempotent
- Jobs re-check state before mutating
- Business rules live in services, not jobs
- Jobs are safe to retry

## 🚀 Deployment (Render + Vercel)

X-Bid is deployed across two platforms:

### Backend
- **Render**
- PostgreSQL
- Background workers
- ActionCable support

### Frontend
- **Vercel**
- Static assets + edge delivery
- Environment-based configuration

### Design principles

- Backend owns all secrets
- Frontend never trusts itself
- Clear environment separation (dev / staging / prod)
- Safe rollback paths

## 🧠 Patterns to Know (and Keep)

- Command vs Query separation
- Admin vs Public boundaries
- Explicit authorization via command objects
- Hybrid JWT + session model
- Pessimistic locking for bids
- Idempotent payments and jobs

These patterns are intentional.  
If you find yourself fighting them, stop and re-evaluate.

## 📚 Related Docs (Recommended Next Reads)

- Authentication & Session Lifecycle
- Authorization
- Domain Boundaries
- Commands vs Queries
- Concurrency & Locking
- Payments & Credits

## 🧾 TL;DR

X-Bid favors:

- Explicit boundaries over clever abstractions
- Server authority over client trust
- Safety over convenience
- Clarity over magic

If a change blurs a boundary, it’s probably the wrong change.
