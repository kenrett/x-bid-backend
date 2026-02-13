# X-Bid Backend

This is the Ruby on Rails API backend for the X-Bid auction platform. It handles authentication, auctions, bid packs, and real-time bidding.

## Backend Architecture Overview

### Commands (What They Are)
- One file = one action (e.g., `Auctions::PlaceBid`, `Admin::Auctions::Retire`).
- They validate inputs, apply business rules, update data, and return a `ServiceResult`.
- Commands keep controllers thin and replace scattered business logic.

### How Commands Orchestrate Work
Commands read like a short script that calls small helpers:

```ruby
def call
  validate_auction!
  ensure_user_has_credits!
  with_lock_and_retries do
    persist_bid!
    extend_auction_if_needed!
  end
  publish_bid_placed_event
  ServiceResult.ok(data: { bid:, auction: })
end
```

Each helper has a single job, so the flow stays readable and easy to test.

### Domain Events (What They Are)
- Domain events announce that something important happened (e.g., `Auctions::Events::BidPlaced`).
- Commands emit events; listeners (ActionCable, analytics, etc.) react without the command knowing the details.
- Commands perform the action; events publish that it happened—clean separation for future extensions.

### Why We Use This Pattern
- Easier to read and understand; the call method is a high-level script.
- Predictable structure across the codebase; junior-friendly.
- Safer boundaries between admin/public flows.
- More testable: commands and events are tested separately.
- No hidden controller logic; new teammates can onboard faster.

### One-Line Summary
We use command-based application services to perform domain actions, and domain events to announce when something important happens. This keeps the system clean, predictable, and easy for anyone to work on.

## Docs

- `docs/production_hardening_checklist.md` (deploy-day checklist)
- `docs/OPERATIONS.md` (operational runbook)
- `docs/deployment.md` (deployment overview)

## Prerequisites

* Ruby: `3.4.5` (see `.ruby-version`).
* Rails: `~> 8.0.2` (see `Gemfile`).
* Database: PostgreSQL.

## Getting Started

Follow these steps to get the application running locally.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kenrett/x-bid-backend
    cd x-bid-backend
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    ```

3.  **Configure the database:**
    Ensure you have a PostgreSQL user that can create databases. Update `config/database.yml` if your local setup requires a specific username or password.

4.  **Create and seed the database:**
    This will create the database, run all migrations, and populate the database with sample users, bid packs, and auctions.
    ```bash
    bin/rails db:create db:migrate db:seed
    ```

5.  **Run the server:**
    ```bash
    bin/rails server
    ```
    The API will be available at `http://localhost:3000`.

**Shortcut:** `bin/setup` runs `bundle install`, then `db:create db:migrate db:seed`.

### Running Tests

```bash
bin/test
```

### Linting & Security

```bash
bin/lint  # runs rubocop and brakeman
```
CI also runs bundler-audit to check Gemfile.lock for vulnerable dependencies.
Run lint/security checks before merging.

### API schema drift check

Regenerate the OpenAPI spec (CI will fail if `docs/api/openapi.json` is out of date):

```bash
bundle exec rails openapi:generate
```

### Canonical OpenAPI artifact (for frontend CI/dev)

Use the generated JSON file at `docs/api/openapi.json` as the single canonical artifact to feed client generation/validation.

```bash
bundle exec rails openapi:generate
```

- Canonical file path (in this repo): `docs/api/openapi.json`
- CI artifact: job `openapi_drift` uploads `openapi-json` containing `openapi.json` (and `docs/api/openapi.json`).
- Determinism: running `bundle exec rails openapi:generate` repeatedly produces identical output (canonicalized + deep-sorted).
- Frontend environment example: `OPENAPI_SPEC_PATH=/path/to/x-bid-backend/docs/api/openapi.json`
- Local dev alternative (when the backend is running): fetch the raw spec from `http://localhost:3000/api-docs.json` (or `http://localhost:3000/docs.json`).

## Architecture checks

Ensure public services do not reference admin namespaces:

```bash
bundle exec rails test test/services/architecture_test.rb
```

If a public service (for example `app/services/auctions/place_bid.rb`) referenced
`Admin::Auctions::Upsert`, the test would fail and list the offending file path.

Run privileged-attribute guardrails to ensure non-admin actors cannot change admin-only auction fields:

```bash
bundle exec rails test test/integration/auctions_privileged_attributes_test.rb
```

### Service results

All services should return a `ServiceResult` with `ok?`, `code`, `message`, and optional
`data` (and `record` for convenience). Prefer `ServiceResult.ok(code: :ok, message: "done", data: {...})`
and `ServiceResult.fail("reason", code: :some_error)`. Controllers should render
errors as `{ error: { code, message } }` using `result.code`/`result.message`.

## For Contributors / Local Development

* Setup: `bin/setup` (installs gems, creates/migrates/seeds DB)
* Run tests: `bin/test`
* Lint & security: `bin/lint` (rubocop + brakeman)
* Git hooks: `lefthook install` to enable pre-commit hooks (runs `bin/lint` and `bin/test`)
  * Pre-commit runs `bundle exec rubocop` for fast feedback.
  * Pre-push runs `bin/test` and `bin/lint` (rubocop + brakeman).

## Configuration

The app relies on the following environment/config values:

* `SECRET_KEY_BASE`: JWT signing secret (required in production).
* `DATABASE_URL`: primary database connection (see `config/database.yml`).
* `QUEUE_DATABASE_URL`: optional override for Solid Queue (defaults to `DATABASE_URL`).
* `REDIS_URL`: required in production for cache/rate limiting.
* `FRONTEND_URL`: base URL for password reset links and checkout returns (defaults to `http://localhost:5173`).
* `FRONTEND_WINS_URL`: optional override for win-claim links (defaults to `FRONTEND_URL` + `/wins`).
* `FRONTEND_ORIGINS` or `CORS_ALLOWED_ORIGINS`: CORS allowlist overrides.
* `SESSION_COOKIE_DOMAIN` and `COOKIE_SAMESITE`: optional cookie scoping overrides.
* `SESSION_TOKEN_IDLE_TTL_MINUTES`: optional idle session timeout override (defaults to 30 minutes).
* `SESSION_TOKEN_ABSOLUTE_TTL_MINUTES`: optional absolute session lifetime override (defaults to 1440 minutes / 24 hours).
* `SESSION_TOKEN_TTL_MINUTES`: legacy alias for idle timeout (used when `SESSION_TOKEN_IDLE_TTL_MINUTES` is unset).
* Stripe keys: `STRIPE_API_KEY`, `STRIPE_WEBHOOK_SECRET` (required for checkout flows).
* Mailer SMTP settings for production delivery.
* Active Storage S3: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`, optional `AWS_ENDPOINT`, `AWS_FORCE_PATH_STYLE`.

---

## API Documentation

Interactive API docs are served by `oas_rails`. Once the server is running, you can access the documentation in your browser at:

* **http://localhost:3000/api-docs**
* **http://localhost:3000/docs** (redirects to `/api-docs`)

The documentation provides a complete list of endpoints, parameters, and example responses. The list below is a high-level overview.

### API Endpoints Overview

All endpoints are prefixed with `/api/v1`.

### Response Envelopes

* `GET /auctions` returns an envelope: `{ auctions: [ ... ] }` (newest-first bid ordering is applied via association defaults).
* Other single-resource endpoints return the resource JSON directly (e.g., `{ id: ..., title: ... }`).

### Authentication

* `POST /users` and `POST /signup`: Register a new user and create a session.
* `POST /login`: Create a session. Response always includes `session_token_id` and `user`, and includes `access_token`/`refresh_token` only when bearer auth is enabled. Also sets signed HttpOnly cookies (`bs_session_id` for HTTP and `cable_session` for `/cable`).
* `POST /session/refresh`: Rotate session tokens and re-issue session cookies (supported for clients that use refresh tokens).
* `GET /session/remaining`: Session TTL remaining for the authenticated session.
* `DELETE /logout`: Revoke the active session server-side and clear session cookies.
* `GET /logged_in`: Check whether the current session is valid.
* HTTP authentication is cookie-first via signed `bs_session_id`; bearer tokens are a compatibility fallback and may return `X-Auth-Deprecation: bearer`.
* Bearer access tokens include `iat`/`nbf` claims and are verified on decode.
* `POST /password/forgot` and `POST /password/reset`: Request and complete password resets.
* `POST /email_verifications/resend` and `GET /email_verifications/verify`: Email verification.

### Auctions

* `GET /auctions`: Get a list of all auctions (no pagination today).
* `GET /auctions/:id`: Get details for a single auction.
* `POST /auctions/:id/extend_time`: Extend auction time (admin only).
* `POST /auctions/:id/watch` and `DELETE /auctions/:id/watch`: Watch/unwatch an auction.
* `POST /auctions`: Create a new auction (admin only).
* `PATCH /auctions/:id`: Update an auction (admin only).
* `DELETE /auctions/:id`: Retire an auction (sets status to inactive; 422 if bids exist or already inactive).

### Bidding

* `POST /auctions/:auction_id/bids`: Places a bid on an auction. Requires authentication + verified email (`403` `email_unverified` if unverified).
* `GET /auctions/:auction_id/bid_history`: Retrieves the list of bids for a specific auction (newest-first by `created_at`).

### Bid Packs

* `GET /bid_packs`: Get a list of available bid packs for purchase.
* `POST /api/v1/admin/bid-packs` and `PATCH/PUT/DELETE /api/v1/admin/bid-packs/:id`: Admin CRUD for bid packs (DELETE retires a bid pack; hard delete is blocked to preserve purchase history). Reactivation allowed via update (`status: "active"` or `active: true`).

### Checkout (Bid Pack Purchases)

* `POST /checkouts`: Create a Stripe Checkout session. Requires authentication + verified email (`403` `email_unverified` if unverified).
* `GET /checkout/status`: Fetch a Stripe checkout session status.
* `GET /checkout/success`: Apply a successful checkout (idempotent) and credit the user. Requires authentication + verified email (`403` `email_unverified` if unverified).

### Account, Wallet, and Profile

* `GET /account` and `PATCH /account`: View/update account.
* `POST /account/password`: Change password.
* `GET /account/security`: Security settings (2FA status, etc.).
* `POST /account/2fa/setup`, `POST /account/2fa/verify`, `POST /account/2fa/disable`: 2FA flows.
* `POST /account/email-change`: Start email change.
* `GET /account/notifications` and `PUT /account/notifications`: Notification preferences.
* `GET /account/sessions`, `DELETE /account/sessions`, `DELETE /account/sessions/:id`: Session management.
* `GET /account/data/export`, `POST /account/data/export`, `GET /account/export/download`: Account data export.
* `GET /wallet` and `GET /wallet/transactions`: Credits and wallet history.
* `GET /me` and related endpoints for purchases, activity, wins, and notifications.
* `POST /me/wins/:auction_id/claim`: Claim a win.

### Uploads

* `POST /uploads`: Create a signed upload.
* `GET /uploads/:signed_id`: Stream uploaded content by signed id (`Cache-Control: public, max-age=31536000, immutable`).

### Admin & Audit

* `GET /api/v1/admin/users`: List admin/superadmin users (superadmin only). Member actions to grant/revoke admin/superadmin and ban users.
* `GET /api/v1/admin/payments`: List purchases with optional `search=userEmail` filter.
* `GET /api/v1/admin/payments/:id`: Payment details.
* `POST /api/v1/admin/payments/:id/refund` and `POST /api/v1/admin/payments/:id/repair_credits`: Payment actions.
* `POST /api/v1/admin/audit`: Create an audit log entry `{ action, target_type, target_id, payload }`.
* `POST /api/v1/admin/fulfillments/:id/process`, `.../ship`, `.../complete`: Fulfillment workflow.
* `GET /api/v1/maintenance`: Public maintenance flag `{ maintenance: { enabled, updated_at } }` (no auth).
* `GET /api/v1/admin/maintenance` and `POST /api/v1/admin/maintenance`: Superadmin-only maintenance mode status/toggle.

### Health and Diagnostics

* `GET /api/v1/health`: Basic health check.
* `GET /cable/health`: Action Cable health.
* `GET /up`: Rails health check.

---

## Core Concepts

### Service Objects

Complex business logic is encapsulated in service objects to keep controllers lean and logic reusable. A prime example is the `Auctions::PlaceBid` service (`app/services/auctions/place_bid.rb`), which handles the entire process of placing a bid. This includes:
*   Validating auction status and user credits.
*   Using a database transaction with row-level locking to prevent race conditions.
*   Decrementing user credits.
*   Creating the `Bid` record.
*   Updating the auction's `current_price` and `winning_user`.
*   Extending the auction's `end_time` if the bid is placed in the final seconds.

### Lock Ordering

To prevent deadlocks, any service that needs to lock both a `User` and an `Auction` must acquire locks in that order (user first, then auction). Use `LockOrder.with_user_then_auction` (`app/services/lock_order.rb`) instead of calling `lock!` directly on those models. The bidding flow already follows this pattern.

### Query Objects (Read Models)

Read concerns live in dedicated query objects instead of controllers. For example, `Auctions::Queries::PublicIndex` and `Auctions::Queries::PublicShow` (`app/services/auctions/queries/`) own the projections and eager-loading used by public auction endpoints. This keeps controllers focused on HTTP concerns and gives a single place to adjust filters, projections, or preload strategy for reads.

### Real-time Updates

When a bid is successfully placed, the `Auctions::PlaceBid` service broadcasts an update via **Action Cable** on the `AuctionChannel`. This pushes real-time information (new price, winning user, end time) to all subscribed clients, eliminating the need for frontend polling and creating a dynamic user experience.

---

## Code Style

This project uses `rubocop-rails-omakase` for enforcing a consistent Ruby code style. To run the linter, use the following command:

```bash
bundle exec rubocop
```
