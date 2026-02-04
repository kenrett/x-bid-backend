# Subdomain auth compatibility checklist

## Current auth transport

- HTTP API auth is via `Authorization: Bearer <jwt>` (see `ApplicationController#authenticate_request!`).
- WebSocket (ActionCable) auth accepts a JWT via `Authorization` header, `?token=...` query param, or `cookies.encrypted[:jwt]` (see `ApplicationCable::Connection#websocket_token`).

## Required frontend origins

Ensure the frontend origin is one of:

- `https://biddersweet.app`
- `https://www.biddersweet.app`
- `https://afterdark.biddersweet.app`
- `https://marketplace.biddersweet.app`
- `https://account.biddersweet.app`

## CORS requirements for header-based auth

- Allow `Authorization` request header (Bearer JWT).
- Allow `X-Storefront-Key` request header (storefront resolution / policy context).
- Confirm preflight (`OPTIONS`) requests succeed for `/api/*`.

## Cookie notes (only if you add cookie-based HTTP auth later)

- If HTTP auth ever moves to cookies, ensure cookie `Domain=.biddersweet.app` (leading dot) so it is shared across subdomains.
- Use `Secure` + `HttpOnly` and choose `SameSite` based on whether cross-site requests are needed.
