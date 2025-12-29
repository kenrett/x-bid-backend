# Money Loop Smoke Test (Vertical Slice)

This is the canonical end-to-end “money loop” verification: **Checkout → Purchase → Credits → Purchases/Receipts → Refund → Credit reconciliation**.

## Prerequisites

- Backend running locally (Rails) and reachable from the internet for webhooks.
- Frontend running locally (Vite).
- Stripe **test mode** keys configured:
  - Backend:
    - `STRIPE_SECRET_KEY`
    - `STRIPE_WEBHOOK_SECRET`
  - Frontend:
    - `VITE_STRIPE_PUBLISHABLE_KEY`
- One of:
  - **stripe-cli** (recommended), or
  - **ngrok** + Stripe Dashboard webhook endpoint

## Setup

1. Start backend:
   - `bin/rails db:migrate`
   - `bin/rails s`
2. Start frontend:
   - `npm run dev`
3. Ensure at least one active `BidPack` exists (create via Rails console if needed):
   - `bin/rails console`
   - `BidPack.create!(name: "Smoke Pack", bids: 10, price: 9.99, description: "smoke", active: true, status: :active)`

## Webhooks (choose one)

### Option A: stripe-cli (recommended)

1. Login:
   - `stripe login`
2. Forward webhooks to local backend:
   - `stripe listen --forward-to localhost:3000/api/v1/stripe/webhooks`
3. Copy the printed signing secret and set it as `STRIPE_WEBHOOK_SECRET`.

### Option B: ngrok

1. Run:
   - `ngrok http 3000`
2. In Stripe Dashboard (test mode), create a webhook endpoint:
   - URL: `https://<ngrok-host>/api/v1/stripe/webhooks`
   - Events: `checkout.session.completed`, `payment_intent.succeeded`, `charge.refunded`
3. Set the endpoint signing secret as `STRIPE_WEBHOOK_SECRET`.

## Steps

### 1) Login

- In the app, create an account and login.
- Navigate to “Buy bids” and confirm bid packs load.

### 2) Start Checkout

- Select a bid pack.
- Confirm the embedded Stripe Checkout appears.

### 3) Complete Payment (Stripe test)

- Use Stripe test card: `4242 4242 4242 4242`, any future expiry, any CVC/ZIP.
- Confirm redirect to `/purchase-status?session_id=...`.

### 4) Verify Credits Updated

- On the purchase status page, confirm success and the **new balance** is shown.
- Navigate to Wallet and confirm the header balance matches.

### 5) Verify Purchases + Receipt behavior

- From Wallet, click “Purchases”.
- Confirm the purchase appears in the list with:
  - Bid pack name
  - Amount + currency
  - Status `succeeded`
- Click into the purchase detail page:
  - Receipt link is shown **only** if `receiptUrl` exists.
  - Stripe IDs (payment intent/session/event/charge) are visible under “Technical details” when available.

### 6) Verify Admin Payments

- Login as an admin user (or promote a user) and navigate to Admin Payments.
- Confirm the purchase exists and references the same Stripe payment intent.

### 7) Trigger Refund and Verify Reconciliation

Choose one:
- Admin refund in the app, or
- Trigger a test refund in Stripe Dashboard for the payment.

Then verify:
- Purchase status becomes `refunded` (or `partially_refunded`).
- Wallet balance decreases according to the refund policy (proportional-safe).
- Purchases list shows `refunded`.

## Notes

- If `receipt_status` stays `pending` due to Stripe API issues, the daily backfill (`purchases:receipts:backfill`) should eventually populate `receipt_url` when Stripe provides it.
- Idempotency expectations:
  - Replaying the same Stripe webhook event returns OK (idempotent) and does not double-apply credits/refunds.

