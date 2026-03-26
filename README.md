# WAStays MVP

WAStays is a modern hotel platform for small and budget hotels across Malaysia and Southeast Asia. This application provides a full-stack solution for hotel onboarding, inventory management, public booking, and guest arrival workflows.

## Prerequisites

- **Ruby:** 3.3+ (Check `.ruby-version`)
- **Node.js:** 20+
- **PostgreSQL:** 14+
- **Redis:** (Optional, but recommended for background jobs)

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd wastays
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    npm install
    ```

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

Run the full test suite with:
```bash
bundle exec rspec
```

## Documentation

Detailed technical specifications and implementation roadmaps are available in the `markdowns/` directory. Operational guides for admins can be found in `markdowns/guides/`.
