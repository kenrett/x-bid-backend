# Storefront Routing Contract

## Scope
Routing and storefront-key behavior for multi-storefront requests.

## Storefronts
- `biddersweet.app`
- `www.biddersweet.app`
- `afterdark.biddersweet.app`
- `marketplace.biddersweet.app`
- `account.biddersweet.app`

## Contract Rules
1. Requests resolve a storefront context before business logic executes.
2. Storefront-scoped records (auctions, bids, sessions, audit data) include and respect `storefront_key`.
3. Cross-storefront data leakage is not allowed.
4. Unknown storefronts fail closed with explicit error status and payload.

## Operational Checks
- Validate host mapping is configured in production env vars.
- Verify CORS and ActionCable origin allowlists match active storefront domains.
