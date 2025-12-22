# Frontend security headers (Vercel)

Add a `headers` block to `vercel.json` so every response from the SPA carries baseline security headers:

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "Strict-Transport-Security", "value": "max-age=63072000; includeSubDomains; preload" },
        { "key": "Content-Security-Policy", "value": "default-src 'self'; script-src 'self'; style-src 'self'; cconnect-src 'self' https://x-bid-backend.onrender.com wss://x-bid-backend.onrender.com http://localhost:3000 ws://localhost:3000; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" },
        { "key": "Referrer-Policy", "value": "no-referrer" },
        { "key": "Permissions-Policy", "value": "geolocation=(), microphone=(), camera=()" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" },
        { "key": "Cross-Origin-Resource-Policy", "value": "same-site" }
      ]
    }
  ]
}
```

Adjust `connect-src` (and add `font-src`/`img-src` entries) for your API/CDN/analytics domains; replace the `api.example.com` placeholders with the real HTTPS and WSS origins.
