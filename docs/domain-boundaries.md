# 🧭 Domain Boundaries

This document explains **how X-Bid is structured into domains and boundaries**, and why those boundaries matter.

This is the heart of the system. If you understand this file, you’ll know **where code should live**, how to avoid regressions, and how to extend the product without turning it into a ball of mud.

## 🎯 High-Level Goals

These boundaries exist to:

- Keep business logic **discoverable and testable**
- Prevent privilege leaks and “oops we mutated prod state” bugs
- Make it obvious where to implement a new feature
- Reduce accidental coupling between unrelated areas
- Support scaling the codebase without cargo-cult refactors

## 🧱 Public vs Admin Domains

X-Bid is split into two top-level domains:

### Public domain
Public flows are **user-facing**. They may read broadly and mutate narrowly.

Examples:
- Browsing auctions
- Viewing auction details and bid history
- Placing a bid (user-initiated mutation with tight rules)
- Buying bid packs (via Stripe, user-initiated)

Public flows **must not**:
- Mutate privileged attributes
- Override system integrity rules
- Perform “admin-like” actions

### Admin domain
Admin flows are **privileged operations**. They can mutate system state broadly, but must do so through explicit command objects.

Examples:
- Creating/updating/retiring auctions
- Adjusting user credits
- Issuing refunds
- Retiring bid packs
- Force-closing auctions / overriding timing

Admin flows **must**:
- Enforce authorization (`actor.admin?`)
- Be auditable
- Centralize privileged mutations

### Boundary rule

> Any mutation that affects money, timing, visibility, or system integrity must live behind an `Admin::*` command.

If you’re unsure, assume it’s admin-only until proven otherwise.

## 🔀 Command vs Query Separation

X-Bid uses explicit read/write separation:

### Queries (reads)
Queries retrieve and shape data. They do not mutate state.

A query can:
- Filter
- Sort
- Join associations
- Shape output for serializers
- Return paginated results

A query must not:
- Write to the database
- Trigger side effects
- Broadcast events
- “Fix up” invalid data

### Commands (writes)
Commands perform state transitions and coordinate side effects.

A command can:
- Validate business rules
- Mutate state (DB writes)
- Emit domain events / broadcasts
- Trigger background jobs
- Return a structured `ServiceResult`

A command must:
- Be explicit about its intent
- Own the transaction boundary (when needed)
- Be safe under concurrency (when applicable)

## 🧩 What Belongs Where

### ✅ Commands

Commands exist to perform **a business action**.

Commands are the right place for:

- Business invariants and guardrails
- Transactions and locking
- Side effects (broadcasts, job enqueue, audit logs)
- Orchestration across multiple models
- Returning a consistent `ServiceResult`

Examples:
- `Auctions::PlaceBid`
- `Admin::Auctions::Upsert`
- `Admin::Auctions::Retire`
- `Payments::ApplyWebhookEvent` (or similar)

### ✅ Queries

Queries exist to answer **a question**.

Queries are the right place for:

- Index/show shapes for API responses
- Non-trivial join graphs and includes
- Filtering/sorting/pagination
- “View models” for the API

Examples:
- `Auctions::Queries::PublicIndex`
- `Auctions::Queries::PublicShow`
- `Auctions::Queries::AdminIndex`
- `Users::Queries::AdminIndex`

### ✅ Models

Models exist to represent **domain state** and enforce basic integrity.

Models are the right place for:

- Associations
- Validations (shape-level, not business workflows)
- Lightweight derived attributes
- Scopes that are purely read-oriented
- Enum definitions and status representation

Models must not:
- Contain orchestration logic
- Make authorization decisions
- Trigger cross-domain side effects
- Hide writes behind “innocent” methods

A model should be safe to reason about in isolation.

### ✅ Controllers

Controllers exist to translate **HTTP intent** into domain calls.

Controllers are the right place for:

- Authenticating a request
- Parsing params
- Selecting the correct command or query
- Rendering the response shape
- Mapping errors to HTTP status codes

Controllers must not:
- Contain business rules
- Perform direct privileged mutations
- Own complex query logic
- Perform orchestration beyond routing

A controller should remain readable in under a minute.

## 🚫 Anti-Patterns We Explicitly Reject

These are the patterns that create invisible coupling and long-term pain.

### ❌ “Fat controller” business logic
If you see logic beyond routing and rendering, it belongs in a command or query.

### ❌ “Smart model” workflows
Models should not coordinate multi-step business workflows or side effects.

### ❌ Authorization sprinkled everywhere
Authorization must be centralized:
- Public services should not be checking `admin?`
- Admin commands must enforce privilege

### ❌ Queries that mutate
Queries must not write to the DB, enqueue jobs, or broadcast.

### ❌ Commands that return raw ActiveRecord objects without context
Commands should return a consistent structured result:
- success/failure
- code
- errors
- payload

### ❌ Hidden side effects
No callbacks that:
- broadcast
- enqueue jobs
- mutate other records
- apply business rules “magically”

Side effects must be explicit in commands.

### ❌ Crossing boundaries casually
Examples:
- Public flow calling `Admin::*`
- Admin flow reusing a public service that assumes user constraints
- Controllers reaching into models to “just update one field”

If a boundary is crossed, it should be deliberate and documented.

## 🧠 Why This Boundary System Works

Boundaries create mechanical safety:

- Privileged operations are easy to audit
- Reads and writes don’t blur together
- High-risk logic lives where it can be tested
- New features have an obvious “home”
- Refactors don’t accidentally change behavior

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Architecture & Patterns
- Authentication & Session Lifecycle
- Authorization
- Commands vs Queries
- Concurrency & Locking
- Payments & Credits

## 🗂 Files to Look At (Code Pointers)

### Backend
- `app/controllers/api/v1/*`
- `app/services/admin/**`
- `app/services/**`
- `app/queries/**` (or your query namespace)
- `app/models/**`

## 🧾 TL;DR

- Public vs Admin is a **hard boundary**
- Queries read, Commands write
- Controllers route intent
- Models represent state, not workflows
- If code doesn’t have an obvious home, stop and re-check the boundaries
