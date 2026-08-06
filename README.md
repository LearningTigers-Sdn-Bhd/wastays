# WAStays PMS

WAStays is a modern hotel platform for small and budget hotels across Malaysia and Southeast Asia. This application provides a full-stack solution for hotel onboarding, inventory management, public booking, and guest arrival workflows.

## Prerequisites

- **Ruby:** 3.4.7 (see `.ruby-version`, managed via mise)
- **PostgreSQL:** 14+ with pgvector

No Node.js required — the app uses Import Maps and Tailwind via Ruby gems. No Redis required — background jobs, cache, and Action Cable use the database-backed Solid Queue/Cache/Cable.

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd wastays
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    ```
    WAStays is a Rails app that uses Import Maps and Tailwind, so there is no `npm install` step in the default setup.
    Set `RAILS_MASTER_KEY` in your shell or create an untracked `config/master.key` before running Rails commands.

3.  **Setup the database:**
    ```bash
    bin/rails db:setup
    ```
    This will create the database, load the schema, and seed it with essential platform data and a sample hotel.

4.  **Run the application:**
    WAStays uses Tailwind CSS and Import Maps. Use the development script to start the Rails server and CSS watcher:
    ```bash
    ./bin/dev
    ```
    *Note: Do not use `bin/rails s` directly if you want Tailwind styles to recompile automatically.*

5.  **Access the application:**
    Open [http://localhost:3000](http://localhost:3000) in your browser.

## Default Credentials (Development)

- **Superadmin:** `superadmin@wastays.com` / `password`
- **Hotel Owner:** `owner@sample.com` / `password`

## Key Features

- **Multi-Tenancy:** Account and Hotel-based resource isolation.
- **Booking Engine:** Real-time availability, 15-minute inventory holds, and quote snapshots.
- **Payments:** Support for encrypted gateway settings and mock webhook-driven confirmation.
- **Hotel Operations:** Bulk rate/inventory editing, arrival manifest, and internal notes.
- **Superadmin Tools:** Hotel approval workflow, hierarchical margin rules, and reconciliation dashboard.
- **Guest Experience:** PII encryption and automated pre-checkin tracking.

## Testing

Use the domain-aware test runner:

```bash
bin/test
```

By default this runs the fast non-system suite in parallel. Common commands:

```bash
bin/test --menu
bin/test --list
bin/test bookings
bin/test hotel_management
bin/test hotel_operations
bin/test financials
bin/test reports
bin/test system
bin/test all
bin/test spec/models/app_config_spec.rb
bin/test spec/models/app_config_spec.rb:12
```

Use `bin/test <domain> --serial` for serial execution and `bin/test <domain> --paths` to inspect a domain's spec mapping. Raw RSpec remains available with `bundle exec rspec` when needed.

`bin/test` stores per-domain timing data in `tmp/parallel_runtime_rspec_<domain>.log` to improve parallel distribution after the first run.

## Documentation

Domain documentation and plan/design specs live in `docs/` (including `docs/superpowers/plans/` and `docs/superpowers/specs/`). Operational guides for hotel admins are loaded from `guides/`. AI assistant instructions are in `CLAUDE.md`.

## Production Deployment

Production runs on Coolify with separate web and worker resources built from the same `Dockerfile`. The web resource uses `CONTAINER_ROLE=web`, the worker uses `CONTAINER_ROLE=worker`, and both mount the same `/rails/storage` path.

See `docs/coolify/separate-resources.md` for the full setup.
