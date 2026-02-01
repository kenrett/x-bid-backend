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

Production uses S3-backed Active Storage to support multiple web instances. Local disk
remains for development/test and as a temporary safety net during migration.

### The Risk
If you scale to multiple web servers (e.g., `web: [1.2.3.4, 1.2.3.5]`), files uploaded to Server A will be stored on Server A's disk. A user visiting Server B will see broken images.

### Operational Guidance
- Keep the local volume until S3 migration is complete and verified.
- See `docs/storage.md` for required env vars, migration steps, and smoke tests.
