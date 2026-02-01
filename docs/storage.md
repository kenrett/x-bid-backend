# Active Storage (S3)

Production uses S3-backed Active Storage to support multiple web instances. Local
disk remains available for development and test.

## Required environment variables

- `S3_BUCKET`
- `AWS_REGION`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Optional

- `AWS_ENDPOINT` (S3-compatible providers like R2/MinIO)
- `AWS_FORCE_PATH_STYLE` (`"true"` or `"false"`)
- `AWS_SESSION_TOKEN` (temporary credentials)

## Migration: local disk -> S3

Run the backfill task in production after setting the S3 env vars:

```
bin/rails active_storage:backfill_to_s3
```

The task is idempotent and resumable. It uploads missing blobs, verifies checksums,
and updates `service_name` to `amazon` for migrated blobs.

### Batching and ranges

```
BATCH_SIZE=500 START_ID=1000 END_ID=5000 bin/rails active_storage:backfill_to_s3
```

- `BATCH_SIZE` defaults to `1000`
- `START_ID`/`END_ID` are optional, inclusive bounds

## Smoke test (S3)

```
bin/rails storage:smoke
```

This task uploads a small blob to S3, downloads it, verifies the contents, and
purges it. If required S3 env vars are missing, it will skip.

## Rollback strategy

- Keep the local storage volume intact until S3 has been verified.
- If you must rollback the app version, keep S3 env vars set so existing blobs
  continue to resolve.
- Do not remove the local disk volume until you are confident all blobs have
  been migrated and verified.
