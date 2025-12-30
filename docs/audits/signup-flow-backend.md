# Signup Flow (Backend Audit)

## Summary

- There is **no** `POST /api/v1/signup` route in this Rails API.
- “Signup” (user registration) is implemented as **`POST /api/v1/users`** (`Api::V1::UsersController#create`).
- The signup endpoint returns `{ token, user }`, but **does not create a `SessionToken` row** and **does not return a `refresh_token`**.
- The returned signup `token` payload is **not compatible with `authenticate_request!`** (it lacks `session_token_id`), so it will not authenticate against endpoints protected by `authenticate_request!`.

## Routes

From `config/routes.rb:24`:

```rb
# Routes for user registration
resources :users, only: [ :create ]

# Routes for sessions (login/logout)
post "/login", to: "sessions#create"
post "/session/refresh", to: "sessions#refresh"
```

Notes:
- Confirmed: **no** `POST /api/v1/signup` exists (search for “signup” in `config/routes.rb` and `docs/api/openapi.json` returns nothing).

## Signup Endpoint: `POST /api/v1/users`

### Controller/action

- `app/controllers/api/v1/users_controller.rb:7` (`Api::V1::UsersController#create`)

### Implementation facts

- Creates a `User` via `User.new(user_params)` and `user.save` (`app/controllers/api/v1/users_controller.rb:8`).
- On success, returns a JWT created via `encode_jwt(user_id: user.id)` (`app/controllers/api/v1/users_controller.rb:10`).
- Serializes the user via `UserSerializer.new(user).as_json` (`app/controllers/api/v1/users_controller.rb:11`).
- **Does not create a `SessionToken` row** (no call to `SessionToken.generate_for` or `SessionToken.create!` in this action).

### JSON returned (exact shape)

Success (`201 Created`) (`app/controllers/api/v1/users_controller.rb:12`):

```json
{
  "token": "<jwt>",
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
  "errors": [
    "Password can't be blank",
    "Email address has already been taken"
  ]
}
```

## Auth/JWT + Session Token Behavior

### JWT encoding method

- `ApplicationController#encode_jwt` is defined at `app/controllers/application_controller.rb:97`.
- Default expiration is 24 hours if `expires_at` is not provided (`app/controllers/application_controller.rb:98`).

### What `authenticate_request!` expects

- `authenticate_request!` looks for `session_token_id` inside the decoded JWT and loads `SessionToken` by that ID (`app/controllers/application_controller.rb:14` to `app/controllers/application_controller.rb:18`).

Implication:
- The signup token is created as `encode_jwt(user_id: user.id)` with **no `session_token_id`** (`app/controllers/api/v1/users_controller.rb:10`).
- Therefore, requests using this token against endpoints protected by `authenticate_request!` will fail with `401` (“Session has expired”) because `SessionToken.find_by(id: nil)` returns `nil` and `session_token&.active?` is false (`app/controllers/application_controller.rb:15` to `app/controllers/application_controller.rb:18`).

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

- Does this create `SessionToken` on signup (`POST /api/v1/users`)? **N**
- Does this return `refresh_token` on signup (`POST /api/v1/users`)? **N**
- Does this align with FE contract? **N (signup returns a JWT that is not usable with `authenticate_request!` because it lacks `session_token_id`; login/refresh use a different contract)**

