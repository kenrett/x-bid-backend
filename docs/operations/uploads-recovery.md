# Upload Recovery Runbook

## 1) Audit S3 vs ActiveStorage

```bash
bundle exec rake uploads:audit AWS_BUCKET=<bucket> AWS_REGION=<region>
```

Optional prefix filter:

```bash
bundle exec rake uploads:audit AWS_BUCKET=<bucket> AWS_REGION=<region> UPLOADS_PREFIX=uploads/
```

Output report:

`uploads_audit.json`

## 2) Rehydrate auction image URLs from attached blobs

Dry run:

```bash
bundle exec rake uploads:rehydrate_auction_image_urls DRY_RUN=1
```

Only fill missing image_url values:

```bash
bundle exec rake uploads:rehydrate_auction_image_urls DRY_RUN=1 ONLY_MISSING=1
```

Apply:

```bash
bundle exec rake uploads:rehydrate_auction_image_urls
```

## Notes

- If `SECRET_KEY_BASE` changed, old signed IDs become invalid and can return 404 even when S3 objects still exist.
- Rehydration regenerates signed IDs and updates `Auction.image_url`.
