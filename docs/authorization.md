# 🔐 Authorization

This document explains **how authorization works in X-Bid**, covering:

- Admin vs public boundaries
- Role checks (`admin?`, future roles)
- Where authorization **must not** live
- How admin commands enforce privilege
- Examples of forbidden mutations

Authorization answers **what you can do**, after authentication has established **who you are**.

## 🎯 High-Level Goals

This authorization system is designed to:

- Enforce **clear public vs admin boundaries**
- Centralize privileged mutations in explicit command objects
- Prevent accidental or implicit authorization checks
- Make permission failures **predictable, auditable, and debuggable**
- Ensure future roles can be added without refactoring core flows


## 🧭 Core Concepts

### Authentication vs Authorization

- **Authentication**: Verifies identity (sessions, JWTs, users)
- **Authorization**: Governs permissions (who may mutate what)

Authentication happens *first*.  
Authorization is enforced **at the boundary where state changes occur**.


## 🧱 Admin vs Public Boundaries

X-Bid enforces a **hard separation** between:

### Public domain
- Read-only access to auctions, bids, listings
- User-initiated actions with limited scope (e.g. placing bids)
- Cannot mutate privileged attributes

### Admin domain
- Auction creation, updates, retirement
- User credit adjustments
- Bid pack management
- Payments, refunds, overrides

**Rule:**  
> Any mutation that affects system integrity, money, timing, or visibility must live in an `Admin::*` command.

## 👤 Role Checks

### Current roles

- `admin`
- `user`

Role checks are intentionally **simple and explicit**:

`actor.admin?`

### Future roles

The system is designed so additional roles (e.g. moderator, support) can be introduced by:

- Adding role semantics
- Routing new permissions through explicit command objects
- Avoiding role checks scattered across controllers or models

## 🚫 Where Authorization Must Not Live

To keep authorization consistent and auditable, authorization must not live in:

#### ❌ Controllers

- Controllers authenticate requests
- Controllers route intent
- Controllers do not decide who is allowed to mutate state

#### ❌ Models

- Models should not know who is acting
- Callbacks with implicit authorization are forbidden
- Model methods should not silently enforce permissions

#### ❌ Views / Frontend

- UI can hide controls
- UI does not provide security
- Backend authorization is always authoritative

## ✅ Where Authorization Does Live
### Admin command objects

All privileged mutations are routed through explicit admin commands, for example:

- `Admin::Auctions::Upsert`
- `Admin::Auctions::Retire`
- `Admin::Users::AdjustCredits`
- `Admin::Payments::IssueRefund`

Each admin command:

- Receives an `actor`
- Verifies `actor.admin?`
- Fails fast with a forbidden result if unauthorized
- Performs the mutation only after authorization succeeds

This ensures **no privileged mutation occurs accidentally.**

## 🔐 How Admin Commands Enforce Privilege

A typical admin command enforces authorization at initialization or execution:

- Validate the actor’s role
- Reject unauthorized callers immediately
- Log or surface authorization failures consistently

This creates a single, auditable choke point for sensitive operations.

## 🚧 Examples of Forbidden Mutations

The following patterns are explicitly disallowed:

#### ❌ Controller-level mutation
`Auction.update!(status: :inactive)`

#### ❌ Model method with hidden privilege
```ruby
class Auction
  def retire!
    update!(status: :inactive)
  end
end
```

#### ❌ Public service mutating admin-only fields
`Auctions::ExtendAuctionTime.call(...)`

#### ✅ Correct pattern
`Admin::Auctions::Retire.call(actor: current_user, auction:)`


Authorization is **obvious, intentional, and centralized.**

## 🧠 Why This Architecture Is Intentional
### Why not sprinkle `admin?` checks everywhere?

Scattered authorization checks lead to:

- Inconsistent behavior
- Missed edge cases
- Privilege escalation bugs
- Painful audits

Centralized authorization creates mechanical safety.

### Why enforce boundaries at the command layer?

Because commands represent intent to change state.

If a command is privileged:

- Authorization is mandatory
- The boundary is explicit
- The mutation is reviewable

This keeps the system secure even as complexity grows.

📚 Related Docs (Recommended Next Reads)
<!-- TODO (Add links) -->

- Authentication & Session Lifecycle
- Domain boundaries
- Commands vs Queries
- Payments and credits authorization
- Concurrency and locking

## 🗂 Files to Look At (Code Pointers)
### Backend

- `app/controllers/application_controller.rb`
- `app/services/admin/base_command.rb`
- `app/services/admin/auctions/*`
- `app/services/admin/users/*`
- `app/services/admin/payments/*`

## 🧾 TL;DR

Authentication proves who you are.
Authorization controls what you are allowed to do.

In X-Bid:

- Authorization lives in admin commands
- Privileged mutations are explicit
- Forbidden paths are structurally impossible

## 📊 Authorization Lifecycle (Flow Diagram)

```mermaid
flowchart TD
  %% Entry point
  Client[Client / Frontend] -->|Request| Controller[API Controller]
  Controller -->|authenticate_request!| AuthN[Authentication]
  AuthN -->|Sets current_user as actor| Actor[actor = current_user]

  %% Route by domain boundary
  Controller -->|Public endpoint| PublicFlow[Public Flow]
  Controller -->|Admin endpoint| AdminFlow[Admin Flow]

  %% Public flow
  subgraph Public["Public Domain (User-Initiated)"]
    PublicFlow --> PublicCmd[Public Command / Service]
    PublicCmd --> PublicPolicy{Authorization needed?}
    PublicPolicy -->|No - safe mutation| PublicMutate[Allowed mutation<br/>e.g. place bid updates price]
    PublicPolicy -->|Yes - privileged field| Forbidden1[Reject forbidden]
    PublicMutate --> PublicResult[Return ServiceResult]
  end

  %% Admin flow
  subgraph Admin["Admin Domain (Privileged Mutations)"]
    AdminFlow --> AdminCmd[Admin Command]
    AdminCmd --> AdminCheck{actor.admin?}
    AdminCheck -->|No| Forbidden2[Reject forbidden]
    AdminCheck -->|Yes| AdminMutate[Privileged mutation<br/>create update retire]
    AdminMutate --> Audit[Audit log / AppLogger]
    Audit --> AdminResult[Return ServiceResult]
  end

  %% Responses
  Forbidden1 -->|403| Response403[HTTP 403 Forbidden]
  Forbidden2 -->|403| Response403
  PublicResult -->|200 or 4xx| ResponseOK[HTTP Response]
  AdminResult -->|200 or 4xx| ResponseOK

  %% Hard rules
  Controller -.-> Rule1["Controllers route intent only<br/>no authorization logic"]
  PublicCmd -.-> Rule2["Public services must not mutate<br/>admin-only attributes"]
  AdminCmd -.-> Rule3["All privileged mutations go<br/>through Admin commands"]
  Actor -.-> Rule4["Models do not know the actor<br/>no hidden authorization"]
