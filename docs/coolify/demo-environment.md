# Coolify Demo Environment Setup

This project supports a dedicated demo deployment that runs in `RAILS_ENV=demo` while matching production behavior as closely as possible.

## Goal
- Production stays isolated on `wastays.com`
- Demo runs on `demo.wastays.com`
- Demo uses separate databases, separate credentials, and separate app resources
- Demo keeps the same runtime shape as production:
  - web + worker split
  - `solid_cache`
  - `solid_queue`
  - `solid_cable`
  - shared `/rails/storage`

## Demo resources
Create these Coolify resources:
- `wastays-demo-db`
- `wastays-demo-web`
- `wastays-demo-worker`

## Demo databases
Inside the demo PostgreSQL resource, create:
- `wastays_demo`
- `wastays_demo_cache`
- `wastays_demo_queue`
- `wastays_demo_cable`

The app is already configured to derive the cache, queue, and cable database names from `DEMO_DATABASE_URL`.

## Demo web resource
- Build pack: `Dockerfile`
- Dockerfile path: `Dockerfile`
- Public domain: enabled
- Domain: `demo.wastays.com`
- Persistent storage: mount `/rails/storage`
- Start command: leave empty so the image entrypoint handles startup

Environment variables:
- `RAILS_ENV=demo`
- `RAILS_MASTER_KEY=<value from config/credentials/demo.key>`
- `DEMO_HOST=demo.wastays.com`
- `DEMO_PROTOCOL=https`
- `DEMO_DATABASE_URL=postgres://<user>:<password>@<db-host>:5432/wastays_demo`
- `RAILS_LOG_LEVEL=info`
- `RAILS_SERVE_STATIC_FILES=1`
- `PORT=80`
- `SOLID_QUEUE_IN_PUMA=false`
- `CONTAINER_ROLE=web`

## Demo worker resource
- Build pack: `Dockerfile`
- Dockerfile path: `Dockerfile`
- Public domain: disabled
- Persistent storage: mount `/rails/storage`
- Use the same `/rails/storage` volume as the demo web resource
- Start command: leave empty so the image entrypoint handles startup

Environment variables:
- `RAILS_ENV=demo`
- `RAILS_MASTER_KEY=<value from config/credentials/demo.key>`
- `DEMO_HOST=demo.wastays.com`
- `DEMO_PROTOCOL=https`
- `DEMO_DATABASE_URL=postgres://<user>:<password>@<db-host>:5432/wastays_demo`
- `RAILS_LOG_LEVEL=info`
- `CONTAINER_ROLE=worker`

## First boot
After the demo web resource can reach PostgreSQL, run:

```bash
bin/rails db:create db:migrate RAILS_ENV=demo
bin/rails db:seed RAILS_ENV=demo
```

The demo seed path is isolated:
- [db/seeds.rb](/home/sienz/coding/lt-tech-team/wastays/db/seeds.rb)
- [db/demo_seeds.rb](/home/sienz/coding/lt-tech-team/wastays/db/demo_seeds.rb)

## Verification
- `https://demo.wastays.com/up` returns `200`
- generated links use `demo.wastays.com`
- worker starts without crash looping
- demo data is present after seeding
- production data and credentials remain completely separate

## Notes
- Do not reuse production databases for demo
- Do not reuse production credentials for demo
- Keep demo and production on separate Coolify app resources even though both use the same codebase
