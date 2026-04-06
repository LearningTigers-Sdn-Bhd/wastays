# Coolify Separate Resources Setup

## Resources
- `wastays-db`: PostgreSQL managed resource
- `wastays-web`: application resource built from repo `Dockerfile`
- `wastays-worker`: application resource built from repo `Dockerfile`

## Database resource
Create these databases inside the PostgreSQL instance:
- `wastays_production`
- `wastays_production_cache`
- `wastays_production_queue`
- `wastays_production_cable`

Use the managed PostgreSQL resource credentials in Coolify when composing `DATABASE_URL`:
- `<db-host>` is the host name or internal service address shown by Coolify for the PostgreSQL resource. Use the database resource's address, not the app resource host or an external DNS name.
- `<password>` is the password configured for the PostgreSQL user in the Coolify DB resource.

## Web resource
- Build pack: Dockerfile
- Dockerfile path: `Dockerfile`
- Start command: leave empty so the image default startup path runs
- Public domain: enabled
- Persistent storage: mount `/rails/storage`
- The `/rails/storage` mount should point to the same persistent volume path used by the worker resource so both processes read and write the same uploaded files and Active Storage blobs.

Environment variables:
- `RAILS_ENV=production`
- `RAILS_MASTER_KEY=<value from config/credentials/production.key>`
- Store this key in Coolify as an environment variable; do not commit the secret into the repository.
- `DATABASE_URL=postgres://lttechteam:<password>@<db-host>:5432/wastays_production`
- `RAILS_LOG_LEVEL=info`
- `RAILS_SERVE_STATIC_FILES=1`
- `PORT=80`
- `SOLID_QUEUE_IN_PUMA=false`
- `CONTAINER_ROLE=web`

## Worker resource
- Build pack: Dockerfile
- Dockerfile path: `Dockerfile`
- Start command: leave empty so the image default startup path runs
- Public domain: disabled
- Persistent storage: mount `/rails/storage`
- Use the same `/rails/storage` persistent volume path as the web resource.

Environment variables:
- `RAILS_ENV=production`
- `RAILS_MASTER_KEY=<value from config/credentials/production.key>`
- Store this key in Coolify as an environment variable; do not commit the secret into the repository.
- `DATABASE_URL=postgres://lttechteam:<password>@<db-host>:5432/wastays_production`
- `RAILS_LOG_LEVEL=info`
- `CONTAINER_ROLE=worker`

## Verification
- Web resource health check should return `200 OK` from `/up`.
- Web runtime logs should still show:
  - `[docker-entrypoint] Preparing database`
  - `[docker-entrypoint] Database is ready`
- Worker resource should start successfully with `./bin/jobs start` and continue running without an immediate crash loop.
- Rails should boot against the `DATABASE_URL`-driven four-database setup by confirming connections to:
  - `wastays_production`
  - `wastays_production_cache`
  - `wastays_production_queue`
  - `wastays_production_cable`
