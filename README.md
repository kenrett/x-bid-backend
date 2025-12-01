# README

This is the Ruby on Rails API backend for the **X-Bid** auction platform. It handles user authentication, auction management, bid packs, and real-time bidding logic.

## Prerequisites

*   **Ruby:** See the `.ruby-version` file.
*   **Rails:** See `Gemfile` for the exact version (`~> 8.0.2`).
*   **Database:** PostgreSQL

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
    bin/rails db:setup
    ```

5.  **Run the server:**
    ```bash
    bin/rails server
    ```
    The API will be available at `http://localhost:3000`.

---

## API Documentation

This project uses `apipie-rails` to generate interactive API documentation. Once the server is running, you can access the documentation in your browser at:

*   **http://localhost:3000/api-docs**

The documentation provides a complete list of endpoints, parameters, and example responses. The list below is a high-level overview.

### API Endpoints Overview

All endpoints are prefixed with `/api/v1`.

### Authentication

*   `POST /users`: Register a new user.
*   `POST /login`: Log in to receive a JWT.
    * Response includes `is_admin` and `is_superuser` flags (also returned by session refresh).
*   `DELETE /logout`: Log out (for client-side session clearing).
*   `GET /logged_in`: Check if the current user's JWT is valid.
*   `POST /session/refresh`: Refresh the active session token.

### Auctions

*   `GET /auctions`: Get a list of all auctions.
*   `GET /auctions/:id`: Get details for a single auction.
*   `POST /auctions`: Create a new auction (admin only).
*   `PATCH /auctions/:id`: Update an auction (admin only).
*   `DELETE /auctions/:id`: Delete an auction (admin only).

### Bidding

*   `POST /auctions/:auction_id/bids`: Places a bid on an auction. Requires authentication.
*   `GET /auctions/:auction_id/bid_history`: Retrieves the list of bids for a specific auction.

### Bid Packs

*   `GET /bid_packs`: Get a list of available bid packs for purchase.
*   `POST /api/v1/admin/bid_packs` and `PATCH/PUT/DELETE /api/v1/admin/bid_packs/:id`: Admin CRUD for bid packs (DELETE is a soft deactivate).

### Admin & Audit

*   `GET /api/v1/admin/users`: List admin/superadmin users (superadmin only). Member actions to grant/revoke admin/superadmin and ban users:  
    `POST /api/v1/admin/users/:id/grant_admin`, `.../revoke_admin`, `.../grant_superadmin`, `.../revoke_superadmin`, `.../ban`.
*   `GET /api/v1/admin/payments`: List purchases with optional `search=userEmail` filter (admin/superadmin).
*   `POST /api/v1/admin/audit`: Create an audit log entry `{ action, target_type, target_id, payload }` (admin/superadmin).
*   Audit logs are also written automatically for admin actions such as auction create/update/delete, bid pack create/update/deactivate, and admin role changes/bans.

---

## Core Concepts

### Service Objects

Complex business logic is encapsulated in service objects to keep controllers lean and logic reusable. A prime example is the `PlaceBid` service (`app/services/place_bid.rb`), which handles the entire process of placing a bid. This includes:
*   Validating auction status and user credits.
*   Using a database transaction with row-level locking to prevent race conditions.
*   Decrementing user credits.
*   Creating the `Bid` record.
*   Updating the auction's `current_price` and `winning_user`.
*   Extending the auction's `end_time` if the bid is placed in the final seconds.

### Real-time Updates

When a bid is successfully placed, the `PlaceBid` service broadcasts an update via **Action Cable** on the `AuctionChannel`. This pushes real-time information (new price, winning user, end time) to all subscribed clients, eliminating the need for frontend polling and creating a dynamic user experience.

---

## Code Style

This project uses `rubocop-rails-omakase` for enforcing a consistent Ruby code style. To run the linter, use the following command:

```bash
bundle exec rubocop
```
