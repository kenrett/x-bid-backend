# Content Security Policy

The API sets its Content-Security-Policy via `config/initializers/security_headers.rb`. A per-request nonce is generated for scripts so inline JS stays blocked without needing `'unsafe-inline'`.

Current directives:
- `default-src 'self'`
- `script-src 'self' https://js.stripe.com https://static.cloudflareinsights.com 'nonce-{per-request}'`  
  *Stripe Checkout embeds and Cloudflare Insights beacon loader are allowed.*
- `connect-src 'self' https://cloudflareinsights.com`  
  *Cloudflare Insights sends telemetry to this origin.*
- `frame-ancestors 'none'`
- `base-uri 'none'`
- `form-action 'self'`

If additional third-party scripts are introduced, prefer external files from allow-listed origins or add nonce-bearing inline tags, and extend CSP minimally with a clear justification.
