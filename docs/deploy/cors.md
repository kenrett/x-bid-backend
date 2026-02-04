# CORS

## Credentialed browser requests

The API and Action Cable endpoints require credentialed CORS requests. We only allow explicit origins and always set `Access-Control-Allow-Credentials: true` for approved origins. Wildcard origins are never used with credentials.

### Allowed origins

Production:

- https://biddersweet.app
- https://www.biddersweet.app
- https://afterdark.biddersweet.app
- https://marketplace.biddersweet.app
- https://account.biddersweet.app

Development/test:

- http://localhost:5173
- http://afterdark.localhost:5173
- http://marketplace.localhost:5173

### Covered endpoints

- `/api/*`
- `/cable`

### Verification

Request specs assert that every allowed origin receives `Access-Control-Allow-Origin` equal to the origin and `Access-Control-Allow-Credentials: true` on preflight responses. Disallowed origins must not receive permissive headers.
