# 📜 Architecture Decision Records (ADR)

This directory contains **Architecture Decision Records (ADRs)** for X-Bid.

ADRs capture *why* a technical decision was made, not just *what* was implemented.  
They exist to prevent future “why did we do this?” debates and to make architectural intent durable over time.

Each ADR should be:
- Short
- Opinionated
- Time-stamped
- Explicit about tradeoffs

Once written, ADRs are **append-only**. If a decision changes, add a new ADR that supersedes the old one.

## 📁 Directory Structure

```text
/docs/adr
  001-jwt-with-session-tokens.md
  002-command-query-separation.md
  003-actioncable-vs-pure-polling.md
  004-pessimistic-locking-for-bids.md
```

## 🧠 Why ADRs Matter

#### Without ADRs:

- Architecture devolves into folklore
- Decisions get re-litigated repeatedly
- New engineers “simplify” critical safeguards
- Bugs are reintroduced unintentionally

#### With ADRs:

- Intent is preserved
- Tradeoffs are explicit
- Change is deliberate
- History is respected

## 🧾 TL;DR

ADRs document why, not just what.

If you find yourself explaining a design choice more than once,
it belongs in /docs/adr/.