# Signup Flow (Backend Audit)

## Summary

- `POST /api/v1/signup` (`Api::V1::RegistrationsController#create`) is the canonical signup endpoint and returns a **login-equivalent, session-bound** auth payload.
- `POST /api/v1/users` (`Api::V1::UsersController#create`) is a **legacy alias** of `/api/v1/signup` and returns the same session-bound contract.
- Signup now **creates a persisted `SessionToken` row**, returns a `refresh_token`, and issues a JWT containing `session_token_id` so it is compatible with `authenticate_request!`.

## Email Verification Gating (Money Actions)

Signup can create an authenticated session for a user whose email is not yet verified. For money / wallet-impacting actions, the API requires a verified email:

- Blocked when `current_user.email_verified?` is false:
  - `POST /api/v1/auctions/:auction_id/bids`
  - `POST /api/v1/checkouts`
  - `GET /api/v1/checkout/success`
- Error response (via `render_error`):
  - HTTP: `403`
  - `error.code`: `email_unverified`
  - `error.message`: `Email verification required`

## Routes

From `config/routes.rb:24`:

```rb
# Routes for user registration
resources :users, only: [ :create ]
post "/signup", to: "registrations#create"

# Routes for sessions (login/logout)
post "/login", to: "sessions#create"
post "/session/refresh", to: "sessions#refresh"
```

Notes:
- Confirmed: `POST /api/v1/signup` exists and routes to `Api::V1::RegistrationsController#create` (`config/routes.rb:26`).

## Signup Endpoint: `POST /api/v1/users`

### Controller/action

- `app/controllers/api/v1/users_controller.rb:7` (`Api::V1::UsersController#create`)

### Implementation facts

- Creates a `User` and returns the **same session-bound payload** as `/api/v1/signup` using `SessionToken.generate_for` + `Auth::SessionResponseBuilder`.

### JSON returned (exact shape)

Success (`201 Created`):

```json
{
  "token": "<jwt (includes session_token_id)>",
  "refresh_token": "<raw refresh token>",
  "session_token_id": 123,
  "session": {
    "session_token_id": 123,
    "session_expires_at": "2025-01-01T00:00:00Z",
    "seconds_remaining": 1800
  },
  "is_admin": false,
  "is_superuser": false,
  "redirect_path": null,
  "user": {
    "id": 123,
    "name": "Example User",
    "role": "user",
    "emailAddress": "example@example.com",
    "bidCredits": 0
  }
}
```

User fields come from `UserSerializer` (`app/serializers/user_serializer.rb:1`).

Failure (`422 Unprocessable Content`) (`app/controllers/api/v1/users_controller.rb:14`):

```json
{
  "error": {
    "code": "validation_error",
    "message": "Password can't be blank",
    "field_errors": {
      "password": [
        "can't be blank"
      ]
    }
  }
}
```

## Auth/JWT + Session Token Behavior

### JWT encoding method

- `ApplicationController#encode_jwt` is defined at `app/controllers/application_controller.rb:97`.
- Default expiration is 24 hours if `expires_at` is not provided (`app/controllers/application_controller.rb:98`).

### What `authenticate_request!` expects

- `authenticate_request!` looks for `session_token_id` inside the decoded JWT and loads `SessionToken` by that ID (`app/controllers/application_controller.rb:14` to `app/controllers/application_controller.rb:18`).

Implication:
- Signup issues a JWT that includes `session_token_id`, and both `/api/v1/signup` and `/api/v1/users` create a persisted `SessionToken` row (via `SessionToken.generate_for` + `Auth::SessionResponseBuilder`).

## Session + Refresh Token Endpoints

These are separate from signup:

### Login: `POST /api/v1/login`

- Handler: `app/controllers/api/v1/sessions_controller.rb:18` (`Api::V1::SessionsController#create`)
- Creates a persisted session token row and a raw refresh token via `SessionToken.generate_for` (`app/controllers/api/v1/sessions_controller.rb:25`).
- Returns `{ token, refresh_token, session, user, ... }` (`app/controllers/api/v1/sessions_controller.rb:106`).

### Refresh: `POST /api/v1/session/refresh`

- Handler: `app/controllers/api/v1/sessions_controller.rb:40` (`Api::V1::SessionsController#refresh`)
- Validates the raw refresh token by hashing and looking up a `SessionToken` digest (`SessionToken.find_active_by_raw_token`) (`app/controllers/api/v1/sessions_controller.rb:41`, `app/models/session_token.rb:23`).
- Revokes the old session token and issues a new one (`app/controllers/api/v1/sessions_controller.rb:49` to `app/controllers/api/v1/sessions_controller.rb:53`).

## Required Yes/No Answers

- Does this create `SessionToken` on signup (`POST /api/v1/users`)? **Y**
- Does this return `refresh_token` on signup (`POST /api/v1/users`)? **Y**
- Does this align with FE contract? **Y (signup issues a session-bound JWT containing `session_token_id` and matches login/refresh contract)**
