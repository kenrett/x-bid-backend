# 🧪 Testing

This document explains **how testing is expected to work in X-Bid**, covering:

- What must be unit tested
- What must be integration tested
- What doesn’t need tests
- Concurrency test expectations
- Real-time test strategy (or explicit tradeoffs)

Testing in X-Bid exists to prevent regressions in the system’s highest-risk areas: **bidding, credits, payments, authorization, and session invalidation**.

## 🎯 High-Level Goals

This testing approach is designed to:

- Catch regressions before they hit production
- Make risky domains safe to change (bids, credits, payments)
- Encourage refactoring by keeping tests stable and intention-revealing
- Avoid slow, brittle test suites that nobody trusts
- Balance confidence with developer velocity

## ✅ What Must Be Unit Tested

Unit tests are for **business rules and pure decision logic**.

### Commands (write paths)
Every command that mutates state must have unit tests covering:

- Happy path success
- Expected business rule failures (not exceptions)
- Authorization failures (`forbidden`)
- Edge cases that could break invariants

Examples:
- `Auctions::PlaceBid`
- `Admin::Auctions::Upsert`
- `Admin::Users::AdjustCredits`
- Payment/credit grant commands

What to assert:
- returned `ServiceResult` (`success?`, `code`, errors)
- state transitions (price changes, credit consumption)
- no side effects occur on failure (no partial writes)

### Queries (read paths)
Non-trivial queries must have unit tests covering:

- filters/sorts/pagination correctness
- association loading shape (no N+1 regressions if you enforce it)
- boundary scoping (public vs admin views)

What to avoid:
- testing ActiveRecord internals
- snapshot tests of entire JSON payloads unless they are stable and intentional

### Authorization rules
Authorization logic must have unit tests ensuring:

- admin commands reject non-admin actors
- public paths cannot mutate privileged attributes
- forbidden mutations are structurally impossible

### Credit accounting rules
Credit-related rules must be unit tested:

- consuming credits only on accepted bids
- preventing negative balances
- idempotent grant behavior

## 🔗 What Must Be Integration Tested

Integration tests are for verifying **wiring across layers**.

### API request/response behavior
For key endpoints, include integration tests that verify:

- authentication required vs `@no_auth` routes
- correct status codes (401/403/422/404)
- request shape and response shape are stable enough to depend on
- validation errors are properly surfaced

Suggested minimum set:
- session creation (`POST /sessions`)
- session validation/remaining endpoint (if present)
- public auctions index/show
- bid placement endpoint
- checkout creation endpoint
- webhook endpoint signature handling (see below)

### Payments and webhooks
Payment flows must include integration tests for:

- webhook signature verification behavior
- idempotent webhook handling (same event twice)
- credit granting on confirmed payment
- safe failure responses (no double grant)

If you can’t fully simulate Stripe easily, test at least:
- your webhook controller dispatch + idempotency behavior
- your “apply payment event” command against representative payloads

### Admin boundary enforcement
Admin endpoints should have integration tests verifying:

- admin access works
- non-admin access fails with 403
- privileged changes are not reachable via public endpoints

## 🚫 What Doesn’t Need Tests

Be intentional about what *not* to test.

### Do not unit test:
- Rails framework behavior
- ActiveRecord association mechanics
- simple validations that are already covered indirectly
- trivial one-line controllers whose only job is routing

### Do not over-test:
- serializers/blueprints with massive snapshot tests unless stable and intentional
- UI details that will churn frequently (unless they are critical flows)

### Use judgment:
If a test is constantly rewritten without catching bugs, it’s probably noise.

## 🔒 Concurrency Test Expectations

Concurrency is real, and bidding is the hot zone.

### What must be tested
At minimum, the bid system must have tests proving:

- two concurrent bids do not corrupt auction state
- winner and price reflect correct ordering
- credits are not double-consumed
- extension window logic behaves correctly under contention
- retry logic handles retryable DB errors safely

### How to test concurrency (practical options)
You can test concurrency using one or more of these approaches:

- **Threaded test** that fires two bid placements at once and asserts invariants
- **Transaction + locking simulation** where one bid holds lock while another waits
- **Retry simulation** by stubbing retryable exceptions in a controlled way

### What to assert (invariants)
- `current_price` increases deterministically
- only one “current winner” exists
- no duplicate credit spend occurs
- end_time never moves backward
- no partial writes on failure

If you can’t reliably test “true concurrency” in CI, explicitly document the tradeoff and still test the invariants using deterministic lock simulation.

## ⚡ Real-Time Test Strategy (and Tradeoffs)

Real-time is notoriously difficult to test perfectly. The goal is to test what matters without building a flaky suite.

### What must be tested
- session invalidation broadcasts when a session is revoked/disabled
- auction updates broadcast after successful bid mutations
- broadcasts do not leak privileged fields

### Recommended approach
Prefer testing the **event emission layer**, not the socket transport.

That means:
- test that `Auctions::Events.bid_placed(...)` is called with correct payload
- test that session invalidation triggers the correct broadcast
- test payload shape and scoping

### Explicit tradeoff
We intentionally do **not** aim to fully test ActionCable transport in all environments because:
- it is slow and flaky in CI
- the Rails framework already tests it
- correctness is enforced by API + DB source-of-truth rules

If you do add ActionCable integration tests:
- keep them minimal (one or two smoke tests)
- treat them as “does the wiring work?” rather than “every message is perfect”

## 🧰 Test Data & Factories

Tests should prefer:
- factories/fixtures with explicit intent
- minimal setup per test
- clear naming for actors and roles (`admin`, `user`)
- realistic auction states (active, ended, extended)

Avoid:
- giant shared setup that hides what matters
- brittle fixtures that lock in irrelevant attributes

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Concurrency
- Real-Time
- Authorization
- Payments
- Credits
- Error Handling

## 🧾 TL;DR

- Unit test all commands, authorization rules, credit accounting, and key queries
- Integration test the critical API flows and payment/webhook wiring
- Concurrency tests must assert invariants and prevent double-spend bugs
- Real-time tests should focus on event emission and payload correctness, with explicit tradeoffs on transport-level testing
