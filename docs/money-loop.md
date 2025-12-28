# Money Loop (End-to-End Financial Lifecycle)

This document explains how money moves through the X‑Bid backend so an engineer can trace any dollar end‑to‑end, from Stripe charge → internal records → credits → bids → auctions.

## Entities (Source of Truth)

- `Purchase`
  - Represents a successful bid-pack payment (usually via Stripe).
  - Key Stripe identifiers: `stripe_payment_intent_id`, `stripe_checkout_session_id`, `stripe_event_id`.
  - Receipt handling:
    - `receipt_url` is optional.
    - `receipt_status` is explicit: `pending`, `available`, `unavailable`.
- `MoneyEvent` (append-only)
  - Represents *all* money movements (cash-like, in cents).
  - `event_type`: `purchase`, `bid_spent`, `refund`, `admin_adjustment`.
  - `amount_cents` is signed:
    - positive = money in (e.g., `purchase`)
    - negative = money out (e.g., `refund`, `bid_spent`)
  - `source_type` / `source_id` links to the “thing” that caused the event.
  - Immutability is enforced at both model and DB trigger level.
- `CreditTransaction` (append-only)
  - Represents *credits* (bid credits) movements, independent of cash.
  - Used to compute credit balance (`Credits::Balance` / `Credits::RebuildBalance`).
- `Bid`
  - Represents placing a bid on an `Auction`.
  - A successful bid consumes exactly one credit and records a `MoneyEvent` (`bid_spent`).

## Primary Flows

### 1) Stripe → Purchase

**Trigger:** Stripe webhook `payment_intent.succeeded` (see `Stripe::WebhookEvents::Process`).

**Processing:**
- Creates (or finds) exactly one `Purchase` for the Stripe identifiers (idempotent by Stripe ids).
- Sets `Purchase#status = "completed"`.
- Sets `Purchase#receipt_status`:
  - `available` if a real `receipt_url` was obtained
  - otherwise `pending` (receipt may become available later)

### 2) Purchase → MoneyEvent (purchase)

When a purchase is applied successfully:
- Create exactly one `MoneyEvent`:
  - `event_type = purchase`
  - `amount_cents = Stripe amount`
  - `source_type = StripePaymentIntent`
  - `source_id = stripe_payment_intent_id`

Idempotency is enforced via a unique index on `(source_type, source_id, event_type)` for `money_events`.

### 3) Purchase → Credits

After a `Purchase` is persisted:
- A credit grant is recorded as an append-only `CreditTransaction` (kind `grant`) via `Credits::Apply`.
- Credit application uses an idempotency key derived from the purchase (e.g. `purchase:<purchase_id>:grant`).
- The user’s cached `bid_credits` is kept in sync with the ledger-derived balance.

### 4) Credits → Bids → Auction

When a bid is placed (`Auctions::PlaceBid`):
- Credits are debited via `Credits::Debit.for_bid!` (one credit per successful bid).
- The bid is persisted and the auction price/winner are updated under locks.
- A `MoneyEvent` is recorded for the bid:
  - `event_type = bid_spent`
  - `amount_cents = -1`
  - `source_type = Bid`
  - `source_id = bid.id`

This happens within the same DB transaction/lock sequence as the credit debit so concurrency cannot double-spend.

### 5) Refunds (prepared, not yet exposed in UI)

Refund support is prepared via `Payments::IssueRefund`:
- Calls the payment gateway to issue a Stripe refund.
- Records a `MoneyEvent`:
  - `event_type = refund`
  - `amount_cents = -refund_amount_cents`
  - `source_type = StripePaymentIntent`
  - `source_id = original stripe_payment_intent_id`
- **Non-goal:** does not automatically adjust credits yet.

## System Invariants (Guards + Constraints)

These are the rules the system enforces to keep history traceable and prevent double-application:

### Stripe / Purchase invariants

- **One Stripe payment intent → one Purchase**
  - Purchases are keyed by Stripe identifiers (and guarded defensively in purchase application).
  - Violations are logged with `payment_intent_id`.
- **Stripe “succeeded” must not silently succeed without a Purchase**
  - If Stripe reports success but purchase application fails to return a persisted purchase, we raise and log the violation with `payment_intent_id`.

### Purchase / Credits invariants

- **One Purchase → one credit grant**
  - Implemented via a deterministic idempotency key (`purchase:<id>:grant`) and unique constraints on credit transactions.
- **Credits must not be granted for a purchase without an actual Purchase**
  - The credit grant path logs and raises when `reason == "bid_pack_purchase"` but `purchase` is missing.

### MoneyEvent invariants

- **Append-only**
  - Updates/deletes are rejected at model level and by DB triggers.
- **Idempotency for Stripe payment MoneyEvents**
  - Unique on `(source_type, source_id, event_type)` prevents duplicate purchase/refund rows for the same Stripe payment intent.
- **Source records may be missing**
  - Admin history queries must tolerate missing/unknown `source_type`/`source_id` and still return the underlying `MoneyEvent`.

## Diagram (Mermaid)

```mermaid
flowchart LR
  Stripe[Stripe PaymentIntent] -->|payment_intent.succeeded| Webhook[Stripe::WebhookEvents::Process]
  Webhook --> Apply[Payments::ApplyBidPackPurchase]
  Apply --> Purchase[(Purchase)]
  Apply --> MEp[(MoneyEvent: purchase +amount_cents\nsource: StripePaymentIntent)]
  Apply --> CTg[(CreditTransaction: grant +credits\nidempotent by purchase:<id>:grant)]
  CTg --> Balance[Credits balance (ledger-derived)]
  Balance -->|place bid| PlaceBid[Auctions::PlaceBid]
  PlaceBid --> CTd[(CreditTransaction: debit -1)]
  PlaceBid --> Bid[(Bid)]
  PlaceBid --> MEb[(MoneyEvent: bid_spent -1\nsource: Bid)]
  Bid --> Auction[(Auction state)]
  Purchase -->|manual/admin or future UI| Refund[Payments::IssueRefund]
  Refund --> MEr[(MoneyEvent: refund -amount_cents\nsource: StripePaymentIntent)]
```

## How to Trace “Any Dollar”

### Stripe purchase dollars
1. Start with `stripe_payment_intent_id`.
2. Find the `Purchase` with that `stripe_payment_intent_id`.
3. Find the `MoneyEvent` with:
   - `event_type = purchase`
   - `source_type = StripePaymentIntent`
   - `source_id = <payment_intent_id>`
4. Find the associated credit grant (`CreditTransaction` with idempotency key `purchase:<purchase_id>:grant`).
5. Follow subsequent credit debits (`CreditTransaction kind=debit`) and bid events (`MoneyEvent event_type=bid_spent source_type=Bid`).

### Bid spending
1. Start with `Bid.id`.
2. Find the `MoneyEvent` with:
   - `event_type = bid_spent`
   - `source_type = Bid`
   - `source_id = <bid_id>`
3. Verify the corresponding `CreditTransaction` debit exists for the same user and auction bid action (debits are idempotent by key).

### Refund dollars
1. Start with `stripe_payment_intent_id` (refunds are tied to the original intent).
2. Find refund `MoneyEvent`:
   - `event_type = refund`
   - `source_type = StripePaymentIntent`
   - `source_id = <payment_intent_id>`
3. Note: credits are not automatically adjusted yet (explicit non-goal).

## Explicit Non‑Goals (for now)

- **Refund UI / automatic credit adjustments on refund**
  - Refunds are recorded as `MoneyEvent` entries but do not alter credits automatically yet.
- **Chargebacks / disputes handling**
  - No end-to-end automated support; would require additional `MoneyEvent` types and state transitions on purchases.
- **Reconstructing Stripe receipt links**
  - We store Stripe-provided `receipt_url` when available and otherwise keep `receipt_status` as `pending`.

