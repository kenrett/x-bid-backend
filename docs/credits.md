# 🪙 Credits

This document explains **how credits work in X-Bid**, covering:

- Credit lifecycle
- Expiry rules (if any)
- Admin adjustments
- Anti-fraud assumptions
- Relationship to bids

Credits are **business logic**, not just numbers. They represent purchasing power, incentives, and risk, and must be treated as first-class domain concepts.

## 🎯 High-Level Goals

The credits system is designed to:

- Accurately represent user purchasing power
- Remain consistent under concurrency and retries
- Be auditable and explainable
- Prevent accidental or malicious misuse
- Integrate cleanly with bidding and payments

## 🧠 Core Principles

### Credits are domain state
- Credits are not derived on the fly
- Credits must be persisted and mutated explicitly
- Every credit change should have a reason

### Credits are conservative
- Credits should never go negative
- Credits should never be implicitly created
- Credits should never be silently adjusted

## 🔄 Credit Lifecycle

A credit moves through the system in a predictable lifecycle.

### 1) Credit creation (grant)

Credits are created when:
- A Stripe payment is confirmed (via webhook)
- An admin explicitly grants credits
- A promotional or system grant is issued (future)

Each grant should:
- Be recorded explicitly
- Be idempotent
- Include metadata explaining *why* it exists

### 2) Credit availability

Once granted:
- Credits are immediately available for bidding
- Credit balance reflects the sum of all grants minus all spends
- Balance should be computed from authoritative records or maintained with strict invariants

### 3) Credit consumption

Credits are consumed when:
- A bid is successfully placed and accepted

Important:
- Credits are only consumed for **accepted** bids
- Failed or rejected bids must not consume credits
- Consumption must occur inside the same transactional boundary as bid placement

### 4) Credit exhaustion

When a user has:
- `credits_remaining == 0`

They:
- May browse auctions
- May not place bids
- Should receive a clear, user-facing error explaining why

### 5) Credit reversal (optional / future)

Credits may be reversed in cases such as:
- Refunds (policy-dependent)
- Fraud resolution
- Admin correction

Reversals must:
- Be explicit
- Be auditable
- Respect policy around already-consumed credits

## ⏳ Expiry Rules (If Any)

If credits expire, expiration must be:

- Explicit
- Deterministic
- Enforced consistently

### Recommended rules
If expiration is implemented:
- Each credit grant should have an `expires_at`
- Expired credits should not be spendable
- Expiry should be enforced at bid time, not lazily

### Important notes
- Expiry should not retroactively invalidate bids
- Expiry jobs must be idempotent
- UI should surface upcoming expirations clearly

If no expiry exists:
- This should be documented and intentional
- Future introduction of expiry must consider backward compatibility

## 🧱 Admin Adjustments

Credit adjustments are privileged operations.

### Admin-only actions
Admins may:
- Grant credits
- Revoke credits
- Correct balances
- Apply promotional or compensatory credits

Admins must not:
- Adjust credits silently
- Bypass audit logging
- Mutate balances directly in models or controllers

### Expected admin flow
Admin credit changes should:
- Go through an `Admin::*` command
- Require `actor.admin?`
- Record before/after balances
- Include a human-readable reason

## 🛡 Anti-Fraud Assumptions

The credits system assumes:

- Clients are untrusted
- Requests may be replayed
- Users may attempt to exploit race conditions
- Payment confirmation may arrive late or duplicated

### Defensive measures

- Credits are granted only after confirmed payment
- Credit grants are idempotent
- Bid placement enforces sufficient credits under lock
- Credits are checked and consumed atomically with bids
- Admin adjustments are logged and reviewable

Fraud prevention is layered:
- Payments
- Credits
- Bidding
- Auditing

No single layer is trusted alone.

## 🔗 Relationship to Bids

Credits and bids are tightly coupled.

### Bid placement rules
- A bid may only be placed if sufficient credits exist
- Credit consumption happens only if the bid is accepted
- Credit checks must occur under the same lock as auction mutation
- Credit balance must never go negative due to concurrency

### Important invariants
- One accepted bid consumes exactly one credit (or defined amount)
- Credits are not consumed for rejected bids
- Bid history must align with credit consumption history

### Why this matters
If credit consumption and bid placement are not atomic:
- Users may place “free” bids
- Credits may be double-consumed
- Auction state becomes inconsistent

## ⚠️ Common Failure Modes (Plan For These)

- Duplicate webhook grants → idempotency required
- Concurrent bids → locking required
- Refund after credits spent → policy decision required
- Admin adjustment without audit → forbidden
- UI showing stale balance → must re-sync from API

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Payments
- Concurrency
- Authorization
- Bidding lifecycle
- Error Handling

## 🗂 Files to Look At (Code Pointers)

### Backend
- Credit model(s) and balance tracking
- Credit grant and consumption services
- Bid placement command
- Admin credit adjustment commands
- Payment-to-credit integration

### Frontend
- Credit balance display
- Insufficient credit UX
- Purchase / upsell flows

## 🧾 TL;DR

Credits are first-class domain entities.  
They are granted explicitly, consumed atomically, and adjusted only by admins.  
They must be auditable, concurrency-safe, and tightly integrated with bidding.
