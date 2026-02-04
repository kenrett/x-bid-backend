# 🔐 Authentication & Session Lifecycle

This document explains how authentication works end-to-end in X-Bid, covering:

- Login request flow
- Session token creation
- JWT usage
- Frontend session hydration
- Why this design supports revocation, real-time invalidation, and safety

## 🎯 High-Level Goals

This authentication system is designed to:

- Allow server-side session revocation (unlike pure JWT auth)
- Support real-time logout when sessions are invalidated
- Keep the frontend and backend continuously in sync
- Be explicit, observable, and debuggable

## 🔄 Authentication & Session Lifecycle
### Step-by-Step Explanation

### 1. User submits credentials (Frontend)

The user enters their email and password into the login form.

The frontend sends a request to create a session:

`POST /api/v1/sessions`

#### Expected result

On success, the backend responds with a token payload:

- JWT
- Session identifiers
- User metadata

### 2. Backend verifies credentials and creates a `SessionToken`

`SessionsController#create`:

- Verifies credentials
- Rejects invalid or disabled users
- Creates a SessionToken row in the database

#### Why this matters

- The `SessionToken` row is the true source of truth
- A user can be logged out server-side by revoking the session, even if their JWT hasn’t expired

### 3. Backend issues a JWT referencing the `SessionToken`

- The backend signs a JWT containing session_token_id
- The JWT is used for request authentication
- Session validity is still governed by the database row

#### This hybrid model provides:

- Stateless authentication headers
- Immediate server-side session revocation

### 4. Frontend persists session details

The frontend stores session data in localStorage, typically:

- token (JWT)
- refreshToken (if implemented)
- sessionTokenId
- user

These values are used to hydrate session state when the app reloads.

### 5. AuthProvider hydrates and maintains session state

On page load, the frontend `AuthProvider`:

- Reads session values from `localStorage`
- Sets in-memory auth state (current user, token, etc.)
- Starts polling session validity (e.g. `/api/v1/session/remaining`)
- Connects to `ActionCable` for real-time events (including invalidation)

`AuthProvider` becomes the frontend’s single source of truth for authentication.

### 6. Authenticated application routes render

Once the session is hydrated:

- Protected routes are accessible
- API requests include: `Authorization: Bearer <JWT>`
    
On the backend, `ApplicationController#authenticate_request!`:

- Decodes the JWT to extract session_token_id
- Loads the SessionToken
- Rejects requests if revoked or expired
- Rejects disabled users (optionally revoking and broadcasting invalidation)

## 🧠 Why This Architecture Is Intentional
### Why not pure JWT?

Pure JWT systems are awkward for:

- Immediate server-side revocation
- Forced logout when a user is disabled
- Admin invalidation without waiting for token expiry

By tying JWTs to `SessionToken` rows, you keep JWT convenience while retaining server-side control.

### Why poll and use WebSockets?

Two complementary safety nets:

#### Polling (e.g. `/api/v1/session/remaining`)
- Handles silent expiry
- Keeps UI countdowns accurate
- Works even if WebSockets are blocked

#### ActionCable (`SessionChannel`)

- Instant logout when sessions are revoked or users are disabled
- Admin or server-side changes take effect immediately

If either mechanism fails, the other still protects the system.

## 🛡️ CSRF Token Flow (SPA)

For browser-based requests without an Authorization header, the frontend must fetch a CSRF token:

1. `GET /api/v1/csrf` returns `{ csrf_token: "..." }` JSON.
2. The response also sets a signed `csrf_token` cookie that is `HttpOnly`.
3. The frontend keeps the JSON token in memory and sends it as `X-CSRF-Token` on unsafe requests.

The backend validates that the `X-CSRF-Token` header matches the signed cookie value. No localStorage is required.

## 📚 Related Diagrams (Recommended Next Reads)

<!-- TODO (Add links) -->
- Session invalidation (polling + ActionCable) 
- PlaceBid concurrency flow (lock ordering + retry + broadcast)
- Stripe webhook idempotency and purchase crediting
- Auction close → settlement snapshot → retry window expiry job

## 🗂 Files to Look At (Code Pointers)
### Backend

- `app/controllers/application_controller.rb`
- `app/controllers/api/v1/sessions_controller.rb`
- `app/models/session_token.rb`
- `app/channels/application_cable/connection.rb`

### Frontend

- `src/features/auth/providers/AuthProvider.tsx`
- `src/services/cable.ts`
- `src/api/client.ts`

## 🧾 TL;DR

`JWT`s authenticate requests.
`SessionToken` rows authorize sessions.
`ActionCable` keeps everyone honest in real time.

## 📊 Authentication & Session Lifecycle (Flow Diagram)
```mermaid
flowchart TD
  User --> LoginForm
  LoginForm -->|POST /api/v1/sessions| SessionsController
  SessionsController --> SessionToken
  SessionToken --> JWT
  JWT --> FrontendStorage
  FrontendStorage --> AuthProvider
  AuthProvider --> App

  LoginFormNote["User submits email and password<br/>from the login form"]
  SessionsControllerNote["Validates credentials<br/>Creates SessionToken row<br/>Returns JWT payload"]
  SessionTokenNote["Server source of truth<br/>Can be revoked or expired<br/>Controls session validity"]
  JWTNote["JWT contains session_token_id<br/>Sent in Authorization header<br/>Decoded on each request"]
  StorageNote["Saved in localStorage<br/>token, refreshToken, sessionTokenId, user"]
  AuthProviderNote["Hydrates auth state on load<br/>Starts polling and ActionCable<br/>Provides auth context"]
  AppNote["Protected routes available<br/>Auctions, bids, admin"]

  LoginForm -.-> LoginFormNote
  SessionsController -.-> SessionsControllerNote
  SessionToken -.-> SessionTokenNote
  JWT -.-> JWTNote
  FrontendStorage -.-> StorageNote
  AuthProvider -.-> AuthProviderNote
  App -.-> AppNote
