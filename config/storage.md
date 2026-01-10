# Storage Strategy

## Local Storage Volume

The deployment configuration defines a volume for `/rails/storage`:

```yaml
volumes:
  - "x_bid_backend_storage:/rails/storage"
```

### What this is for
- **Active Storage:** User uploads (avatars, auction images) when using the `local` service in `config/storage.yml`.

### What this is NOT for
- **Database:** The production database is PostgreSQL (external or accessory), not SQLite. No database files are stored here.

## Scaling Considerations

Currently, the application uses local disk storage for uploads. This works for a single server (`web`).

### The Risk
If you scale to multiple web servers (e.g., `web: [1.2.3.4, 1.2.3.5]`), files uploaded to Server A will be stored on Server A's disk. A user visiting Server B will see broken images.

### The Fix (Before Scaling)
Before adding more web servers, you must switch `config/storage.yml` to use a cloud provider (S3, GCS, Azure, R2).