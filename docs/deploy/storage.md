# Storage (Active Storage)

## Current State (Local Disk)

Production currently persists uploads on a local disk volume mounted at `/rails/storage`.
This relies on the `local` service in `config/storage.yml` and the volume entry in
`config/deploy.yml`.

## Why This Breaks at 2+ Web Servers

With multiple web servers, each instance has its own local disk. A file uploaded on
Server A won't exist on Server B, so image and file links will intermittently break
based on which server handles the request.

## Target Architecture (S3-Compatible Object Storage)

Switch production to a shared object store (AWS S3 or compatible like R2/MinIO). All
instances read/write the same bucket, so uploads are consistent across web servers.

## Required Environment Variables

Set these in your deployment platform (Render/Kamal), not in git:

- `S3_BUCKET` (required)
- `AWS_REGION` (required)
- `AWS_ACCESS_KEY_ID` (required only when not using IAM/instance roles)
- `AWS_SECRET_ACCESS_KEY` (required only when not using IAM/instance roles)
- `AWS_SESSION_TOKEN` (optional, temp credentials)
- `AWS_ENDPOINT` (optional, for S3-compatible providers)
- `AWS_FORCE_PATH_STYLE` (optional, set to `"true"` for some providers)

### Secrets Strategy

- **Kamal**: put credentials in `.kamal/secrets` or your secret store; keep
  `config/deploy.yml` free of real secrets.
- **Render**: set credentials in the service environment variables UI.
- Never commit access keys to the repo.

## Production Switching Behavior

`config/environments/production.rb` uses `:amazon` when `S3_BUCKET` and `AWS_REGION`
are set. Otherwise it falls back to local disk.

## Data Migration Plan (Disk -> S3)

If you already have uploads on disk, backfill them before removing the disk volume.

1. Deploy with S3 env vars set (both `local` and `amazon` remain in `storage.yml`).
2. Run the backfill task:

```
bin/rails active_storage:backfill_to_s3
```

This task reads files from the `local` service and uploads to `amazon`, verifying
checksums during open/upload. It skips keys that already exist in the bucket.

3. Verify spot checks (e.g., view a few images in the UI).
4. When satisfied, you can remove the local disk volume from `config/deploy.yml`.

## Smoke Test (Production-Like)

Run a quick upload/download test against the configured service:

```
bin/rails storage:smoke
```

This creates a temporary blob, downloads it back, compares content, then purges it.

## Operational Safeguards

- **CDN caching**: ensure private assets are not cached publicly. Signed URLs should
  be short-lived, and CDN rules should respect `Cache-Control` headers.
- **ACLs**: the S3 service is configured as private by default. Do not enable public
  ACLs unless you explicitly need public buckets.
