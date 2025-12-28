# Prompt: Update frontend `purchasesApi` to use canonical route

Update the frontend `purchasesApi` so it uses **only** the canonical purchases endpoints:

- List purchases: `GET /api/v1/me/purchases`
- Show purchase: `GET /api/v1/me/purchases/:id`

Notes:

- Older `/api/v1/purchases` endpoints have been removed from the backend. Any remaining frontend calls must be updated.
- Response shapes should remain the same; continue parsing the same JSON fields.

Tasks:

1. Update any hard-coded paths in `purchasesApi` to use `/api/v1/me/purchases`.
2. Update any tests/fixtures/mocks that reference `/api/v1/purchases` to the canonical route.
3. Ensure the app uses exactly one route for purchases everywhere (search for `"/api/v1/purchases"` and remove/replace).
