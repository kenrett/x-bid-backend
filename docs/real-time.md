# 🔄 Real-Time

This document explains **how real-time updates work in X-Bid**, covering:

- What events are broadcast
- Who can subscribe to what
- Session invalidation flow
- Auction updates flow
- Why polling still exists
- Client reconnection strategy

Real-time in X-Bid is designed to improve UX and safety, **without becoming a source of truth**.

## 🎯 High-Level Goals

This real-time system is designed to:

- Deliver low-latency UI updates for bidding and auction state
- Support instant session invalidation (forced logout)
- Keep event streams scoped and secure (no accidental data leakage)
- Remain robust when WebSockets fail (fallbacks exist)
- Avoid “distributed state” bugs by keeping the backend authoritative

## 🧠 Core Principles

### Backend is the source of truth
- Clients never “trust” a broadcast as authoritative
- Broadcasts are **signals**, not state guarantees
- Final truth always comes from the API and database

### WebSockets are best-effort
- Real-time improves responsiveness
- Polling and normal API requests still enforce correctness
- If WebSockets are blocked or flaky, the app remains usable and secure

## 📡 What Events Are Broadcast

X-Bid broadcasts events in a few key categories:

### 1) Auction updates
Used to keep viewers in sync during live bidding.

Examples:
- New bid placed
- Current price updated
- Winning user changed
- End time extended
- Auction closed / settled

### 2) Session events
Used for security and forced logout.

Examples:
- Session revoked
- User disabled
- Token invalidated or expired

### 3) Admin-triggered state changes
Used to reflect privileged changes quickly.

Examples:
- Auction retired
- Auction edited
- Bid pack retired
- Credits adjusted (optional, depending on UX)

## 🔐 Who Can Subscribe to What

Real-time subscriptions must follow the same domain boundaries as the rest of the system.

### Public subscriptions
Public channels should only broadcast **public-safe** data.

Examples:
- Auction state that is visible to any viewer
- Public bid history (if allowed)
- Countdown updates / end-time extensions

Constraints:
- No PII
- No internal admin metadata
- No “hidden” state (e.g. payment details, admin notes)

### Authenticated user subscriptions
Authenticated channels can include user-scoped events.

Examples:
- Session invalidation events
- User-specific credit/balance updates (if implemented)
- User-specific purchase confirmations (optional)

Constraints:
- Must be scoped to `current_user`
- Must reject subscription if session is invalid

### Admin subscriptions
Admin-only channels can include privileged system events.

Examples:
- Moderation actions
- Admin auction edits
- Fraud flags (future)
- Payment/refund operations (future)

Constraints:
- Must enforce `actor.admin?` at subscription time
- Must not be accessible to non-admin sessions

## 🔒 Authorization and Subscription Rules

All real-time subscriptions must:

- Verify authentication on connection
- Verify authorization on subscription
- Reject invalid/expired/revoked sessions
- Treat the session token row as the source of truth

If a session is revoked, the subscription must stop being valid.

## 🧷 Session Invalidation Flow (Real-Time)

Session invalidation is one of the most important real-time flows.

### What triggers invalidation?
- SessionToken revoked
- SessionToken expired
- User disabled
- Admin forces logout

### Expected behavior
1. Backend detects the session is no longer valid
2. Backend broadcasts an invalidation event to the user’s session channel
3. Frontend receives the event and immediately:
   - Clears local session storage
   - Resets `AuthProvider` state
   - Redirects to login (or shows a “signed out” notice)

### Why it matters
This prevents:
- “Zombie sessions” staying active until token expiry
- Disabled users continuing to interact with the system
- Multi-device sessions staying alive after revocation

## 🏷 Auction Updates Flow (Real-Time)

Auction updates keep active bidders and observers synced.

### What triggers auction updates?
- A bid is placed successfully
- Auction end time is extended
- Auction closes (time reached / settlement)
- Admin edits auction state (retire/update)

### Expected behavior
1. Backend command completes mutation (e.g. `PlaceBid`)
2. Backend broadcasts an auction update event
3. Clients update their UI immediately
4. Clients may still refresh via API for canonical state (especially after reconnect)

### Important: broadcasts are not authoritative
A client may receive:
- Events out of order
- Duplicate events
- Late events after reconnect

The UI must tolerate this and re-sync via API when needed.

## 🧯 Why Polling Still Exists

Polling remains intentionally in place for correctness and reliability.

Polling is used for:
- Session validity (“am I still logged in?”)
- Countdown correctness (auction end time)
- Silent expiry handling
- Re-sync after disconnection

### Why not rely on WebSockets alone?
Because WebSockets can fail due to:
- Corporate proxies
- Mobile networks
- Browser throttling
- Tab suspension
- Temporary server disconnects

Polling provides a safety net so the system stays secure and accurate even when real-time is unavailable.

## 🔌 Client Reconnection Strategy

The frontend must assume the socket will drop and re-establish.

### Expectations
On disconnect:
- UI should continue functioning via normal HTTP requests
- Polling continues (or resumes) to preserve safety and correctness

On reconnect:
- Re-subscribe to relevant channels
- Re-fetch canonical state for any active views
  - Auction detail pages should refresh current price and end time
  - AuthProvider should re-check session validity immediately

### Recommended behavior
- Exponential backoff reconnect attempts
- Guard against duplicate subscriptions
- If session is invalid on reconnect, force logout

## ⚠️ Common Failure Modes (Plan For These)

Real-time systems break in boring ways. Design for:

- Duplicate events
- Events arriving out of order
- Client reconnecting with stale local state
- Broadcast succeeds but client missed it
- Client receives an event but API state differs (race timing)

If you can’t tolerate these, the event payload is too “stateful”.
Favor idempotent “here is the latest summary” payloads over “apply this diff” payloads.

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Authentication & Session Lifecycle
- Authorization
- Concurrency & Locking
- Commands vs Queries
- Payments & Credits

## 🗂 Files to Look At (Code Pointers)

### Backend
- `app/channels/application_cable/connection.rb`
- `app/channels/**` (auction/session channels)
- `app/services/**` (event emitters / broadcasters)
- `app/controllers/application_controller.rb` (auth gate)

### Frontend
- `src/services/cable.ts`
- `src/features/auth/providers/AuthProvider.tsx`
- `src/api/client.ts`

## 🧾 TL;DR

ActionCable improves UX and enables instant invalidation, but it is **never the source of truth**.

The backend remains authoritative.  
Polling exists as a safety net.  
Clients must handle disconnects, duplicates, and re-sync safely.
