# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Rails 8 · Ruby 3.4.7 · PostgreSQL + pgvector. No-build: Import Maps (no Node), Tailwind via gem. No Redis: Solid Queue/Cache/Cable.

## Commands

```bash
./bin/dev                        # run app (Rails + Tailwind watch). NOT bin/rails s
bin/rails db:setup               # create + schema + seed
bin/ci                           # rubocop + brakeman + audits + tailwind + full tests
bin/rubocop                      # lint
bin/brakeman --no-pager          # security scan

bin/test                         # default fast suite, parallel
bin/test --list                  # list domains
bin/test <domain>                # bookings|hotel_management|hotel_operations|financials|
                                 #   payments|reports|hotel_concierge|ai_concierge|channels|
                                 #   guest_portal|admin_platform|system|all
bin/test <domain> --serial       # serial run
bin/test <domain> --paths        # show domain's spec paths
bin/test spec/x_spec.rb[:12]     # single file/line
```

Set `RAILS_MASTER_KEY` (or `config/master.key`) before any `rails` command.

## Layout

```
app/
├── controllers/     admin/ api/ corporate_portal/ guest/ hotel_portal/ public/
├── models/          ActiveRecord only — no business logic
├── services/        <- business logic lives here, namespaced by domain (bookings/, folios/, ...)
├── forms/           form objects
├── queries/         query objects
├── presenters/      view-model objects
├── policies/        Pundit authorization
├── jobs/            background jobs (Solid Queue)
├── components/      panels_ui/  <- ViewComponent UI primitive library
└── javascript/
    └── controllers/ Stimulus controllers

config/routes.rb
db/schema.rb
```

## Conventions

- Business logic goes in `services/<domain>/`, one verb-named class per file. Keep it out of models/controllers.
- Multi-tenancy: `AccountScopable` / `HotelScopable` model concerns; `current_hotel` in `ApplicationController`.
- **Any UI work: read `DESIGN.md` first and follow it** (PanelsUI components, semantic tokens, no native selects).
- Always invoke the `rails-expert` skill (and any other Rails-related skills) when available before doing Rails work.
- Prefer the simplest approach; avoid over-engineering and complex solutions.
- Keep code solid and DRY — reuse before adding.
- Consult and align on the approach first; don't jump straight to code.
- Don't trust `docs/`, `guides/`, or references unless explicitly told to; rely on the code.
