All admin-triggered payment mutations (refunds, voids, manual state corrections) must use services under `Admin::Payments::*` that inherit from `Admin::BaseCommand`.

- Controllers and background jobs should **not** call the payment gateway directly or mutate `Purchase` state for admin actions.
- Use `Admin::Payments::IssueRefund` to issue refunds so that authorization, transactions, and audit logging are consistent.
- Additional admin payment commands (e.g., `MarkAsDisputed`, `Void`) should follow the same pattern: authorize via `Admin::BaseCommand`, call a gateway wrapper, update `Purchase`, and emit audit logs with `AppLogger` (and `AuditLogger` where appropriate).
