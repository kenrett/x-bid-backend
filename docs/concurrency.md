# 🔒 Concurrency

This document explains **how X-Bid handles concurrency**, especially around bidding, covering:

- Locking strategy (pessimistic vs optimistic)
- Retry logic
- Extension windows
- Idempotency expectations
- What must never happen concurrently
- Example bid race walkthrough

Bidding is the highest-risk area of the system. Concurrency bugs here are not “edge cases” — they are guaranteed to happen under load.

## 🎯 High-Level Goals

This concurrency strategy is designed to:

- Prevent double-writes and inconsistent auction state
- Ensure bids are processed in a deterministic order
- Keep auction timing logic correct under load
- Make failure modes safe and retryable
- Avoid “ghost winners” and incorrect credit balances

## 🧠 Core Principle

> The database is the arbiter of concurrency.

We do not rely on:
- in-memory locks
- application-level mutexes
- “it probably won’t happen”

We rely on explicit DB-backed locking and transactional guarantees.

## 🔐 Locking Strategy

### Why pessimistic locking (default)

Bids are a classic high-contention write scenario:
- Many users attempt to mutate the same auction row at once
- Each bid depends on the result of the previous bid

For that reason, the safest strategy is:

- **pessimistic locking** on the auction row
- perform bid validation + mutation inside the lock window
- update derived auction state (price, winner, end time) atomically

This ensures:
- only one bid mutates the auction at a time
- the “current price” is never computed from stale state
- extension logic cannot conflict

### When optimistic locking can work

Optimistic locking can be appropriate when:
- contention is low
- writes are rare
- conflicts are acceptable and easy to resolve

Auctions during active bidding are the opposite of that.

If optimistic locking is introduced for any domain object, it must:
- have clear conflict resolution behavior
- have tests that simulate collisions
- never be used for the auction bid hot-path without explicit justification

## 🔁 Retry Logic

Even with pessimistic locking, systems under load will still see:

- lock wait timeouts
- deadlocks (rare but possible)
- transaction conflicts

For this reason, bid placement must be:

- wrapped in a retry mechanism
- limited to a small number of attempts
- safe to rerun without corrupting state

### Expected retry behavior

- Retry only on *retryable* database errors (timeouts / deadlocks)
- Back off slightly between retries (small jitter)
- Fail with a clear, user-facing error if retries exhaust
- Never retry on business-rule failures (auction closed, insufficient credits, etc.)

## ⏱ Extension Windows

X-Bid auctions often extend when bids arrive near the end.

This introduces a second concurrency risk:
- multiple bids arriving near the extension threshold
- multiple processes trying to extend end time concurrently

### Extension rules must be enforced under lock

End time extension must:
- run inside the same locked transaction as bid placement
- be computed against the current authoritative end time
- only extend if the threshold condition is true at execution time

### Common extension pitfalls to avoid

- Extending based on stale end time read before lock acquisition
- Extending multiple times for the same “window” due to parallel updates
- Broadcasting the wrong end time after mutation

**Rule:**
> End time changes must be computed and applied under the same lock that applies the bid.

## ♻️ Idempotency Expectations

Idempotency matters in two places:

### 1) API requests can be duplicated
Clients can double-submit due to:
- network retries
- double clicks
- browser replays after reconnect

Bid placement should be resilient to “same intent twice” scenarios.

### 2) Jobs / side effects can retry
Broadcasts, background jobs, and webhook handlers may retry.

A bid placement command should be safe in the presence of:
- duplicated broadcasts
- repeated “refresh” fetches
- job retries that re-check state

### Practical expectations

- Broadcasting an auction update should be safe to send multiple times
- Client should tolerate receiving duplicate events
- Any background work triggered by bids should re-check state before acting

If you add a client-provided idempotency key for bids later:
- store it with the bid intent
- ensure uniqueness at the DB layer
- return the original result if replayed

## 🚫 What Must Never Happen Concurrently

These invariants must hold even under heavy load:

### Auction state invariants
- Two bids must not “win” simultaneously
- Auction `current_price` must not regress or skip incorrectly
- Auction `winning_user` must reflect the latest accepted bid
- Auction `end_time` must not move backwards

### Credit / bid accounting invariants
- A user must not be charged twice for one accepted bid intent
- Credits must never go negative due to concurrency
- Bid history must match auction state transitions

### Eventing invariants
- Broadcasts must not leak privileged data
- Clients must not get “finalized” states before DB commit
- “Auction closed” must not be broadcast if the auction can still accept bids

**Rule:**
> Broadcast only after the transaction commits successfully (or structure events so they cannot be observed before commit).

## 🏁 Example Bid Race Walkthrough

Scenario:
- Auction A has `current_price = 10`
- End time is in 3 seconds
- Two users (U1 and U2) click “Bid” nearly simultaneously

### Timeline

#### T0: Both requests arrive
- Request R1 (U1) enters bid command
- Request R2 (U2) enters bid command

#### T1: Lock acquisition
- R1 acquires the auction row lock first
- R2 blocks waiting for the lock

#### T2: R1 validates state under lock
R1 checks:
- auction is active
- auction not expired
- U1 has credits
- compute next price
- compute whether extension applies

#### T3: R1 writes bid + updates auction
R1 performs:
- `Bid.create!(auction: A, user: U1, amount: next_price)`
- `Auction.update!(current_price: next_price, winning_user: U1)`
- if within extension window: `Auction.update!(end_time: extended_time)`

All inside the locked transaction.

#### T4: R1 commits
- DB commit succeeds
- R1 broadcasts auction update (post-commit)
- R1 returns success

#### T5: R2 acquires lock
Now R2 runs against updated state:
- `current_price` reflects U1’s bid
- `end_time` may already be extended

#### T6: R2 validates under lock
R2 checks again:
- auction still active
- end time not passed
- U2 has credits
- recompute next price from new current_price
- extension logic based on updated end_time

#### T7: R2 writes and commits
- Creates bid for U2
- Updates auction winner to U2
- Possibly extends again (if still within rules)
- Commits
- Broadcasts
- Returns success

### Why this is correct
- Both bids are serialized through a single authoritative lock
- Each bid is evaluated against the latest committed state
- Extensions are applied deterministically, not as a race

## 🧪 Testing Expectations (Concurrency-Specific)

At minimum, the bidding hot path should have tests for:

- Two concurrent bids: final price and winner correctness
- Extension window: only valid extensions applied
- Insufficient credits under race: no negative credits
- Retryable DB error: command retries and succeeds or fails cleanly
- Broadcast payload reflects committed state

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Real-Time
- Commands and Queries
- Authorization
- Payments & Credits (idempotency patterns)
- Auction lifecycle and settlement

## 🗂 Files to Look At (Code Pointers)

### Backend
- `app/services/auctions/place_bid.rb` (or equivalent)
- `app/services/auctions/extend_auction.rb` (or equivalent)
- `app/models/auction.rb`
- `app/models/bid.rb`
- `app/channels/**` (broadcast paths)

## 🧾 TL;DR

Bids are serialized with **pessimistic DB locking**.  
Retries handle transient DB failures.  
End-time extensions must be computed under lock.  
Idempotency and “must never happen” invariants prevent production incidents.
