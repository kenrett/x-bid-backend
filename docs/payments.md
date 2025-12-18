# 💳 Payments

This document explains **how payments work in X-Bid**, covering:

- Stripe flows (checkout, webhooks)
- Idempotency strategy
- Credit granting
- Refunds (current or planned)
- Admin vs user-initiated actions
- Failure recovery

Payments are a high-risk area: money bugs are reputation killers. The system is designed to be **auditable, idempotent, and recoverable**.

## 🎯 High-Level Goals

This payments system is designed to:

- Treat Stripe as the payment processor, not the source of truth
- Ensure every payment side effect is **idempotent**
- Grant credits only when payment is confirmed
- Support safe retries and recovery after failures
- Keep admin privilege boundaries explicit and enforceable
- Maintain clear audit trails for all financial actions

## 🧠 Core Principles

### Stripe is authoritative for payment status, not business state
- Stripe tells us what happened (paid, failed, refunded)
- X-Bid decides what that means (grant credits, revoke, log, notify)

### Webhooks are the backbone
- Checkout initiates intent
- Webhooks confirm the outcome
- Credits are granted based on webhook-confirmed state (or Stripe-verified state)

### Idempotency is mandatory
Every webhook and credit-granting operation must be safe to re-run.

## 🧾 Stripe Flows

### 1) Checkout flow (user-initiated)

#### Step-by-step
1. User selects a bid pack / purchase option in the frontend
2. Frontend requests a checkout session from the backend
3. Backend creates a Stripe Checkout Session
4. User completes payment in Stripe-hosted UI
5. Stripe redirects the user back to the frontend (success/cancel)

#### Important note
Redirect success is not proof of payment.  
The backend must rely on Stripe’s webhook events (or a server-side verification step) before granting credits.

### 2) Webhook flow (system-authoritative)

Webhooks are how X-Bid learns the real outcome.

#### Step-by-step
1. Stripe sends a webhook event to the backend
2. Backend verifies webhook signature
3. Backend records the event (idempotently)
4. Backend processes the event:
   - mark payment as paid/failed/etc.
   - grant credits (if paid)
   - trigger follow-up work (emails, receipts, etc.)
5. Backend returns 2xx only when safe

## ♻️ Idempotency Strategy

Idempotency prevents:
- double credit grants
- double refunds
- duplicate payment records
- inconsistent state from retries

### Webhook idempotency (required)
Stripe may deliver:
- duplicate events
- out-of-order events
- retries after timeouts

X-Bid must:
- store a unique identifier per Stripe event (e.g. `stripe_event_id`)
- refuse to re-process events already handled
- log and safely return 2xx for duplicates

**Rule:**
> Webhook processing must be “exactly once” from X-Bid’s perspective, even if Stripe sends the same event many times.

### Credit-grant idempotency (required)
Credit granting must also be idempotent:
- ensure a given payment can only grant credits once
- enforce uniqueness at the DB layer if possible (payment_id → credit_grant_record)

**Rule:**
> “Paid” is not enough — credit granting must also track whether it already happened.

## 🪙 Credit Granting

Credits are business state and must be handled explicitly.

### When credits should be granted
Credits should be granted only when:
- Stripe confirms payment success via webhook
- the payment corresponds to a known purchase intent
- the grant has not already been applied

### How credits should be granted
Credit granting should be performed by a command/service that:
- runs in a transaction
- writes an immutable “grant record” (recommended)
- updates the user’s credit balance
- is safe to retry

### Audit expectations
A successful grant should record:
- who it was for
- what was purchased (bid pack)
- how many credits were added
- Stripe payment identifiers
- timestamps
- the webhook event id(s) involved

## 💸 Refunds (Current or Planned)

Refunds are inherently privileged and should be treated as an admin domain feature.

### Current state (if implemented)
- Refunds are initiated by admin commands only
- Refund outcome is confirmed via Stripe events
- Credits may be reversed depending on policy

### Planned state (recommended)
Implement refunds as a dedicated admin command:
- `Admin::Payments::IssueRefund`

Refund policy must be explicit:
- Can credits be revoked after consumption?
- Are refunds partial or full?
- What happens if credits are already spent?

**Rule:**
> Refunds should never be a “quick update” — they are workflows with policy.

## 🧱 Admin vs User-Initiated Actions

### User-initiated
Users may:
- create checkout sessions
- view their own purchase history (read-only)
- see credit balance and receipts

Users may not:
- directly grant credits
- directly mark payments paid
- directly refund or adjust balances

### Admin-initiated
Admins may:
- issue refunds
- adjust credits (with audit)
- inspect payment state
- reconcile and repair inconsistencies (with explicit tooling)

Admin actions must:
- enforce `actor.admin?`
- be auditable
- be reversible when possible

## 🧯 Failure Recovery

Payments must assume things go wrong:
- webhook delivery fails
- database write fails mid-processing
- Stripe event arrives out of order
- background jobs retry
- user refreshes or repeats flows

### Recovery patterns

#### 1) Safe retries
- If webhook processing fails, Stripe retries
- Your code must handle duplicates gracefully

#### 2) Reconciliation
Introduce a reconciliation path (manual or automated) that can:
- re-fetch Stripe payment intent / session status
- compare to internal records
- apply missing credits safely (idempotently)
- flag suspicious inconsistencies

#### 3) Clear states
Model payment state explicitly:
- `created`
- `pending`
- `paid`
- `failed`
- `refunded` / `partially_refunded`
- `disputed` (future)

Avoid “boolean paid” where lifecycle matters.

#### 4) Logging and alerting
For every webhook:
- log event id
- log processing result
- log idempotency decision (processed vs skipped)

High-signal alerts:
- webhook signature failures
- repeated processing failures
- credit grant failures after confirmed payment

## ⚠️ Common Failure Modes (Plan For These)

- Stripe sends the same event multiple times → must not double grant
- Webhook arrives before the redirect success page loads → UI must handle “pending”
- Payment succeeds but credit grant fails → must be recoverable
- Refund issued but credits already spent → policy decision required
- Partial refunds → credit adjustments must reflect policy consistently

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Credits
- Authorization (admin boundary enforcement)
- Real-Time (purchase and balance updates)
- Error Handling
- Deployment (webhook config)

## 🗂 Files to Look At (Code Pointers)

### Backend
- Stripe checkout session creation (controller/service)
- Webhook controller (signature verification + dispatch)
- Payment model(s) and state transitions
- Credit granting service/command
- Admin refund command(s)

### Frontend
- Checkout initiation flow
- Success/cancel pages (and “pending” states)
- Credit balance UI and purchase history

## 🧾 TL;DR

Checkout starts intent. Webhooks confirm truth.  
Credits are granted only after confirmed payment.  
Everything is idempotent.  
Refunds and adjustments are admin-only, audited workflows.  
Failures are expected — recovery paths must exist.
