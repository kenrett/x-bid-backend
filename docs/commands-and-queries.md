# 🔀 Commands and Queries

This document explains **how X-Bid separates reads from writes** using a Command/Query pattern.

The goal is simple: make it obvious **where logic belongs**, keep controllers thin, keep models honest, and prevent “just one little update” from turning into an untestable mess.

## 🎯 High-Level Goals

This Command/Query approach is designed to:

- Keep reads and writes **clearly separated**
- Make business actions **explicit and testable**
- Reduce controller and model complexity
- Improve observability (consistent results + error codes)
- Prevent regressions caused by “helpful” side effects in read paths

## 🧾 What a Command Is

A **Command** performs an intentional business action that **may change state**.

Commands are used for:
- Creating or updating records
- Domain workflows (place a bid, retire an auction, apply a webhook)
- Side effects (broadcasts, jobs, audit logs)
- Concurrency control (locking, retries)

### Command characteristics

A command typically:
- Accepts explicit inputs (actor, params, ids, etc.)
- Validates business rules
- Performs DB writes (often within a transaction)
- Emits side effects deliberately
- Returns a structured `ServiceResult`

### Commands must not
- Hide writes behind “innocent” model methods
- Return random shapes depending on where they were called
- Raise uncaught exceptions for expected business failures
- Mix in complex read shaping (that belongs in queries)

## 🔎 What a Query Is

A **Query** answers a question by retrieving and shaping data **without mutating state**.

Queries are used for:
- Index/show endpoints
- Filtering, sorting, pagination
- Fetching related associations
- Shaping data for serializers / blueprints
- “View models” for API responses

### Query characteristics

A query typically:
- Accepts params (filters, pagination, current_user context if needed)
- Composes scopes and includes
- Returns records or a structured result
- Does **not** write to the database
- Does **not** broadcast or enqueue jobs

### Queries must not
- Update counters or “touch” timestamps
- Repair invalid state
- Perform side effects
- Contain business workflow logic

## 🏷 Naming Conventions

### Commands
- Use **verbs** that describe intent
- Use **domain namespace** first

Examples:
- `Auctions::PlaceBid`
- `Auctions::ExtendAuction` (if user-facing + safe)
- `Admin::Auctions::Upsert`
- `Admin::Auctions::Retire`
- `Payments::ApplyWebhookEvent`

Rule of thumb:
> If you can put it in a sentence like “do X”, it’s a command.

### Queries
- Live under a `Queries` namespace
- Use **noun-ish names** describing the answer shape
- Encode audience context when needed (Public/Admin)

Examples:
- `Auctions::Queries::PublicIndex`
- `Auctions::Queries::PublicShow`
- `Auctions::Queries::AdminIndex`
- `Users::Queries::AdminShow`

Rule of thumb:
> If you can put it in a sentence like “get me X”, it’s a query.

## 📦 Return Types: `ServiceResult`

Both Commands and Queries should return a consistent result object.

### Why `ServiceResult`?

It gives:
- Consistent success/failure handling
- Predictable error codes for controllers
- A clean place to put payload + metadata
- Better logs and observability

### Expected shape (conceptual)

A `ServiceResult` should support:

- `success?`
- `code` (symbol/string identifier)
- `errors` (structured, not just a string)
- `payload` (records or domain objects)
- `meta` (pagination, counts, etc.)

### Example outcomes

- `success` with payload
- `failure` with code + errors
- `forbidden` for authorization failures
- `not_found` for missing records
- `invalid` for validation/business rule failures

## 🚦 Error Handling Expectations

### What should be a failure result vs an exception?

#### Return a failure `ServiceResult` for expected cases:
- Invalid input
- Business rule violations
- Insufficient credits
- Auction closed
- Forbidden access
- Missing records (often)

These are part of normal product behavior.

#### Raise exceptions only for truly unexpected cases:
- Database corruption / invariants violated
- Programmer errors (nil access, impossible states)
- External system failures you cannot handle locally
- Unexpected third-party payload shape

If it can happen “in normal usage”, it should generally be a failure result, not an exception.

## 🧪 How Controllers Should Use Commands/Queries

Controllers should look like this:

- Authenticate request
- Call one command or query
- Render based on `ServiceResult`

Example pattern (conceptual):

- `result = Auctions::PlaceBid.new(...).call`
- `render_success(result.payload)` if `result.success?`
- `render_error(code: result.code, message: result.error, status: result.http_status)` otherwise

Controllers should not:
- Implement business branching
- Query deeply with includes + scopes
- Perform direct mutations

## 🆚 Example: `Auctions::PlaceBid` vs `Auctions::Queries::PublicShow`

### `Auctions::PlaceBid` (Command)

**What it does**
- Validates auction state
- Validates user credits
- Locks auction row to prevent race conditions
- Creates a bid
- Updates auction price / winning user
- Extends end time if needed
- Broadcasts updates
- Returns a `ServiceResult`

**Why it’s a command**
- It changes state
- It has side effects
- It must be concurrency-safe
- It represents an intentional business action

### `Auctions::Queries::PublicShow` (Query)

**What it does**
- Loads auction by id
- Includes associated records (bids, images, etc.)
- Shapes response-ready data (or returns record(s) for a serializer)
- May incorporate viewer context for conditional fields (if needed)
- Returns a `ServiceResult` (or records + metadata)

**Why it’s a query**
- It does not mutate state
- It answers a question: “what should the public see for this auction?”

## ✅ Quick Decision Checklist

If you’re adding new logic, ask:

### Is it a Command?
- Does it write to the DB?
- Does it change auction state, credits, timing, visibility, money?
- Does it broadcast, enqueue a job, or log an audit event?
- Does it require locking or retries?

If yes → Command.

### Is it a Query?
- Does it only read data?
- Does it shape data for an endpoint/view?
- Does it filter/sort/paginate?
- Does it need includes/preloads?

If yes → Query.

If it does both → split it.

## 📚 Related Docs (Recommended Next Reads)

<!-- TODO (Add links) -->
- Domain Boundaries
- Authorization
- Concurrency & Locking
- Real-Time Events
- Payments & Credits

## 🧾 TL;DR

Commands **change state** and return `ServiceResult`.  
Queries **read and shape data** and do not mutate.  
Keeping them separate makes the system safer, easier to test, and harder to accidentally break.
