# README

This is the Ruby on Rails API backend for the **X-Bid** auction platform. It handles user authentication, auction management, bid packs, and real-time bidding logic.

## Prerequisites

*   **Ruby:** See the `.ruby-version` file for the exact version.
*   **Rails:** 8.0
*   **Database:** PostgreSQL

## Getting Started

Follow these steps to get the application running locally.

1.  **Clone the repository:**
    ```sh
    git clone <your-repository-url>
    cd x-bid-backend
    ```

2.  **Install dependencies:**
    ```sh
    bundle install
    ```

3.  **Configure the database:**
    Ensure you have a PostgreSQL user that can create databases. Update `config/database.yml` if your local setup requires a specific username or password.

4.  **Create and seed the database:**
    This will create the database, run all migrations, and populate the database with sample users, bid packs, and auctions.
    ```sh
    bin/rails db:setup
    ```

5.  **Run the server:**
    ```sh
    bin/rails server
    ```
    The API will be available at `http://localhost:3000`.

---

## API Endpoints

All endpoints are prefixed with `/api/v1`.

### Authentication

*   `POST /users` - Register a new user.
*   `POST /login` - Log in to receive a JWT.
*   `DELETE /logout` - Log out (for client-side session clearing).
*   `GET /logged_in` - Check if the current user's JWT is valid.

### Auctions

*   `GET /auctions` - Get a list of all auctions.
*   `GET /auctions/:id` - Get details for a single auction.
*   `POST /auctions` - Create a new auction (admin only).
*   `PATCH /auctions/:id` - Update an auction (admin only).
*   `DELETE /auctions/:id` - Delete an auction (admin only).

### Bidding

*   `POST /auctions/:auction_id/bids` - Place a bid on an auction. Requires authentication.
    *   **Body:** `{ "bid": { "amount": 12.50 } }`

### Bid Packs

*   `GET /bid_packs` - Get a list of available bid packs for purchase.

---

## Core Concepts

### Service Objects

Business logic is encapsulated in service objects to keep controllers lean. For example, `PlaceBid` (`app/services/place_bid.rb`) contains all the logic and validations for placing a bid, including handling transactions, updating user credits, and extending the auction timer.

### Real-time Updates

When a bid is successfully placed, the `PlaceBid` service broadcasts updates via Action Cable on the `AuctionChannel`. This allows connected clients to receive real-time information about the new price and highest bidder without needing to poll the API.
