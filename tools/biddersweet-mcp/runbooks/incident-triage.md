# Incident Triage Runbook

## Purpose
Provide a fast, repeatable path to identify, contain, and recover from production incidents impacting X-Bid backend APIs.

## First 10 Minutes
1. Confirm incident scope:
   - Impacted endpoints and storefronts.
   - First seen time and current error rate.
2. Check platform health:
   - Render service status and latest deploys.
   - API health endpoints: `/up`, `/api/v1/health`.
3. Triage by symptom:
   - `5xx`: inspect app/runtime logs and recent deploy changes.
   - `401/403`: validate auth/session cookie domain/CORS setup.
   - `429`: verify rate-limiter behavior and traffic anomalies.

## Containment
1. Stop harmful automation/jobs if they amplify impact.
2. Roll back to last known good deploy when regression is confirmed.
3. If data integrity is at risk, freeze affected write paths and page owner.

## Recovery Checklist
1. Verify health endpoints return success.
2. Run critical smoke checks for auth, bidding, and checkout.
3. Confirm error rates return to baseline.
4. Communicate recovery and monitor for 30 minutes.

## Evidence to Capture
- Incident start/end timestamps (UTC).
- Affected service IDs and deploy IDs.
- Representative request IDs and stack traces.
- Root cause summary and follow-up action items.
