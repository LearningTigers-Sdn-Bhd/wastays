# E-Invoice Integration Plan

**Source branch:** `origin/feat/e-invoice` (8 commits, diverged from `main` at `eed9263a`, mid-June 2026)
**Target:** current `main` (~1069 commits ahead of the divergence point)
**Goal:** port the LHDN MyInvois e-invoice feature onto current `main` without a straight merge, since large parts of `main`'s hotel-portal UI have been rearchitected since divergence.

Reference: `docs/e-invoice-update-plan.md` on `feat/e-invoice` has the original domain design (requirements, decisions, execution flow). Read it before starting Phase 2 — this plan does not repeat that content, only the integration steps.

## Why not a plain merge

A merge dry-run against current `main` produced **37 conflicted files** (25 content conflicts, 12 modify/delete). The modify/delete conflicts are not noise — `main` deleted the old booking-show/folio/settings partials that `feat/e-invoice` edited, because the booking show page was rebuilt into a new "workspace / action-sheet" architecture (`app/views/hotel_portal/bookings/workspaces/*`, `app/controllers/hotel_portal/bookings/actions/*`) and hotel-portal settings became a page/presenter-driven system (`SettingsController::SETTINGS_PAGES`, `HotelPortal::SettingsPresenter`, per-page routes). The e-invoice branch's UI touchpoints target UI that no longer exists and must be rebuilt against the new structure, not conflict-resolved. The backend/domain layer (`app/services/e_invoice/*`, `app/services/my_invois/*`, jobs, models, migrations) is largely additive and safe to port directly.

## Ground rules for whoever executes this

- Do this on a dedicated branch off current `main`, e.g. `feat/e-invoice-integration`. Do not merge or rebase the old branch directly.
- Port work in the phase order below — each phase depends on the previous one being in place and green.
- After each phase, run the relevant spec subset before moving on. Do not batch all phases into one uncheckable blob of changes.
- Every checkbox should correspond to a real, verifiable unit of work (a file exists, a spec passes, a route resolves). Check it only after verifying, not after writing code.
- Cite exact file paths from this plan; don't rediscover structure from scratch.

---

## Phase 0 — Branch setup

- [ ] Create integration branch from current `main`: `git checkout -b feat/e-invoice-integration main`
- [ ] Add the old branch as a reference remote/tag if not already fetchable: confirm `git show origin/feat/e-invoice:docs/e-invoice-update-plan.md` works
- [ ] Skim `docs/e-invoice-update-plan.md` from `feat/e-invoice` (domain rules, the "Remaining Sign-Off Before Marking Complete" checklist at the bottom — those items were still open when the branch was last touched and are still open now)
- [ ] Confirm current `main`'s migration head and note it: `bin/rails db:migrate:status | tail -5`

---

## Phase 1 — Port the domain/service layer (low risk, additive)

These files don't exist on `main` at all — copy them over as new files, no conflict resolution needed. Use `git show origin/feat/e-invoice:<path>` to pull each one.

### Models
- [ ] `app/models/e_invoice_setting.rb`
- [ ] `app/models/e_invoice_submission.rb`

### Services
- [ ] `app/services/e_invoice/adjustment_note_builder.rb`
- [ ] `app/services/e_invoice/cancel.rb`
- [ ] `app/services/e_invoice/consolidated_batch_builder.rb`
- [ ] `app/services/e_invoice/document_builder.rb`
- [ ] `app/services/e_invoice/issue_adjustment.rb`
- [ ] `app/services/e_invoice/payout_self_billed_document_builder.rb`
- [ ] `app/services/e_invoice/phone_formatter.rb`
- [ ] `app/services/e_invoice/prepare_payout_self_billed_submissions.rb`
- [ ] `app/services/e_invoice/refresh_status.rb`
- [ ] `app/services/e_invoice/submission_context.rb`
- [ ] `app/services/e_invoice/submit.rb`
- [ ] `app/services/e_invoice_pdf_service.rb`
- [ ] `app/services/my_invois/client.rb`
- [ ] `app/services/my_invois/client_factory.rb`
- [ ] `app/services/my_invois/mock_client.rb`
- [ ] `app/services/my_invois/token_store.rb`

### Jobs
- [ ] `app/jobs/e_invoice/auto_issue_job.rb`
- [ ] `app/jobs/e_invoice/issue_adjustment_job.rb`
- [ ] `app/jobs/e_invoice/monthly_consolidation_job.rb`
- [ ] `app/jobs/e_invoice/refresh_status_job.rb`
- [ ] `app/jobs/e_invoice/submit_job.rb`

### Migrations

**Do not copy any migration file across verbatim.** Generate each one fresh with `bin/rails generate migration` so it gets a timestamp above `main`'s current head (`20260818100000_add_hide_payout_reports_to_hotels.rb`), then paste the body in. Three of the stale branch's timestamps are already occupied on `main` by *unrelated* migrations, so a blind copy would collide or shadow:

| Stale-branch timestamp | Already used on `main` by |
|---|---|
| `20260421034024` | `add_channel_manager_fields_to_bookings.rb` (**applied since April** — see hazard below) |
| `20260622000000` | `add_multi_folio_foundation.rb` |
| `20260624000000` | `add_corporate_management_foundation.rb` |

- [ ] **HAZARD — do NOT edit `db/migrate/20260421034024_add_channel_manager_fields_to_bookings.rb`.** The stale branch modified this file in place to add the `fund_collector` column. That file has been applied on every environment since April; Rails tracks migrations by version, not content, so editing it is a silent no-op that will leave `fund_collector` missing in production while appearing correct in the diff. The stale branch already worked around this itself with a separate follow-up migration — port **only** that one (next item).
- [ ] Generate `add_missing_fund_collector_to_bookings` (stale-branch body at `20260622000001`) with a fresh timestamp — this is the migration that actually creates `bookings.fund_collector`
- [ ] Generate `create_e_invoice_submissions` (body from `20260618000002`)
- [ ] Generate `create_e_invoice_settings` (body from `20260618000003`)
- [ ] Generate `harden_e_invoice_submission_indexes` (body from `20260622000000`)
- [ ] Generate `add_tracking_columns_to_e_invoice_submissions`
- [ ] Generate `replace_unique_index_on_e_invoice_submissions` (note the original plan doc's uniqueness-scope fix: `[booking_id, document_scenario, document_type]`, not just `[booking_id, document_scenario]`)
- [ ] Generate `add_guest_city_to_bookings` (body from `20260625090000`) and `add_city_to_guests` — verified clean: neither `bookings.guest_city` nor `guests.city` exists on current `main`
- [ ] **SKIP `20260618005001_add_special_requests_to_booking_quotes_and_bookings.rb`** — this already landed on `main` independently (with an added `unless column_exists?` guard). Do not reintroduce it; the columns are already there.
- [ ] Sanity-check no other collisions before generating: `ls db/migrate | grep -E '20260618|20260622|20260624|20260625'`
- [ ] Run `bin/rails db:migrate` and regenerate `db/schema.rb` naturally (don't hand-merge the conflicted schema.rb from the dry-run)
- [ ] **GATE: do not start the model additions below until `db:migrate` above has succeeded** — those methods reference columns (`fund_collector`, `guest_city`, `guests.city`) that only exist after these migrations run

### Booking / Guest / Hotel / PaymentTransaction model additions
These are additive method blocks, not restructuring — port by hand-adding the methods (don't copy-paste whole files, since `main`'s versions have diverged):
- [ ] `app/models/booking.rb`: add `has_many :e_invoice_submissions`, `FUND_COLLECTORS`, `direct_hotel_payment?`, `payment_concluded?`, `payment_concluded_at`, and all `*_e_invoice_submission` / `e_invoice_*` query methods (see `git diff eed9263a origin/feat/e-invoice -- app/models/booking.rb` for the full additive block — ~189 lines, purely additive)
- [ ] `app/models/guest.rb`: e-invoice-related additions (`git diff eed9263a origin/feat/e-invoice -- app/models/guest.rb`, small)
- [ ] `app/models/hotel.rb`: `has_one :e_invoice_setting` association (small)
- [ ] `app/models/payment_transaction.rb`: additions (small)
- [ ] `app/models/payout_batch.rb`: add `has_many :e_invoice_submissions, dependent: :nullify` (required by the `generate_weekly_batches.rb` hook below)
- [ ] `app/services/booking_engine/confirm_booking.rb`: hook point for payment-concluded e-invoice trigger
- [ ] `app/services/bookings/create_manual_booking.rb`: same hook
- [ ] `app/services/bookings/update_stay_service.rb`: pass `city: booking.guest_city` through the guest-upsert call
- [ ] `app/services/channel_managers/ingest_booking_service.rb`: same hook
- [ ] `app/services/folios/close_for_checkout.rb`: adjustment-note trigger on folio close
- [ ] `app/services/guest_arrival/create_or_match_guest.rb`, `process_pre_checkin.rb`: guest city / e-invoice field wiring
- [ ] `app/services/payments/initialize_checkout.rb`, `process_verification.rb`, `transaction_recorder.rb`: payment-concluded hook
- [ ] `app/services/payout_engine/generate_weekly_batches.rb`: self-billed submission prep hook

### Config
- [ ] `config/recurring.yml`: add `MonthlyConsolidationJob` schedule entry (`cron 5 0 1 * *`) — reconcile with whatever else `main` has added to this file since divergence, don't overwrite
- [ ] `config/credentials/development.yml.enc`: MyInvois dev credentials — coordinate with whoever holds the credentials edit key, re-add via `bin/rails credentials:edit --environment development`, don't attempt to merge the encrypted blob
- [ ] MyInvois production/staging credentials: confirm with the user whether these exist anywhere (1Password, prod credentials file) — not in scope of the git diff

### Phase 1 verification
- [ ] `bin/rubocop app/services/e_invoice app/services/my_invois app/jobs/e_invoice app/models/e_invoice_setting.rb app/models/e_invoice_submission.rb`
- [ ] Port the factories first — specs won't run without them: `spec/factories/e_invoice_settings.rb`, `spec/factories/e_invoice_submissions.rb` (new), plus the additive diffs to `spec/factories/bookings.rb` and `spec/factories/guests.rb`
- [ ] Port and run the pure-domain specs (no controller/view dependency): `spec/services/e_invoice/*`, `spec/services/my_invois/*`, `spec/jobs/e_invoice/*`, `spec/models/e_invoice_submission_spec.rb`, `spec/models/booking_e_invoice_selection_spec.rb`
- [ ] Port the top-level service specs that the `spec/services/e_invoice/*` glob does **not** catch: `spec/services/e_invoice_pdf_service_spec.rb`, `spec/services/e_invoice_services_spec.rb`
- [ ] Port the additive diffs to existing service specs: `spec/services/booking_engine/confirm_booking_spec.rb`, `spec/services/channel_managers/ingest_booking_service_spec.rb`, `spec/services/guest_arrival/create_or_match_guest_spec.rb`, `spec/services/payments/transaction_recorder_spec.rb`, `spec/services/payout_engine/generate_weekly_batches_spec.rb`, `spec/models/guest_spec.rb`
- [ ] Update `spec/services/service_spec_coverage_spec.rb` — this is a meta-spec asserting every service has a matching spec file; the ~17 new service files added in this phase will fail it until it's updated
- [ ] All Phase 1 specs green before starting Phase 2

---

## Phase 2 — Hotel-portal backend touchpoints (medium risk)

These are controllers/routes that exist on both branches but changed independently — reapply the e-invoice-specific behavior against `main`'s current version rather than merging.

- [ ] `app/controllers/hotel_portal/e_invoice_settings_controller.rb` — **do not port this file.** Resolved: `main`'s settings are page/presenter-driven, so this standalone controller has no place. Read it for its `update` logic and permitted-params, then carry that logic into the `SettingsController` + form-object work in Phase 3c. (Previously this step deferred the decision to Phase 3, which risked building it twice.)
- [ ] `app/controllers/hotel_portal/e_invoice_submissions_controller.rb` — new file, port directly (278 lines); check it against current `main`'s `ApplicationController`/base-controller conventions (authorization helpers, `current_hotel`, Pundit patterns may have shifted)
- [ ] `app/controllers/hotel_portal/bookings_controller.rb` — small diff, reapply by hand
- [ ] `app/controllers/hotel_portal/folios_controller.rb` — 34-line diff, reapply by hand against current version
- [ ] `app/controllers/hotel_portal/guests_controller.rb` — small diff, reapply by hand
- [ ] `app/controllers/public/bookings_controller.rb` — **reapply by hand, do NOT copy the file over.** The stale-branch diff shows +107/-0 (it didn't exist at the merge base), but `main` has since created its own 49-line version at that path. Copying would silently clobber it. Add only the e-invoice actions on top of `main`'s current file.
- [ ] `app/controllers/hotel_portal/bookings/show/actions/manage_guests_controller.rb` — 6-line diff; **note this file was deleted on `main`** (booking-show rearchitecture). Find the equivalent under `app/controllers/hotel_portal/bookings/actions/guests_controller.rb` and apply the change there instead.
- [ ] `app/controllers/public/payments_controller.rb` — small diff, reapply by hand (payment-concluded hook)
- [ ] `app/controllers/public/pre_checkins_controller.rb`, `public/concierge/check_ins_controller.rb`, `public/quotes_controller.rb` — small diffs, reapply by hand
- [ ] `app/controllers/guest/bookings_controller.rb` — 115-line addition (guest e-invoice request/status actions); guest controllers were **not** restructured on `main`, so this should port with minimal adaptation
- [ ] `config/routes.rb` — reapply the 24 added lines (e-invoice settings routes, submissions routes, guest request routes) against current route structure; note settings routes are now `scope "settings" do ... get "<page>", to: "settings#index", defaults: { settings_page: "<page>" }` pattern (see Phase 3) — the e-invoice settings route must follow this pattern, not the old ad-hoc route
- [ ] `app/helpers/hotel_portal/navigation_helper.rb` — small diff, reapply (nav entry for e-invoice submissions)

### Phase 2 verification
- [ ] `bin/rails routes | grep -i e_invoice` resolves as expected
- [ ] Port and run the backend-only request specs: `spec/requests/hotel_portal/e_invoice_submissions_spec.rb`, `spec/requests/hotel_portal/folios_spec.rb`, `spec/requests/hotel_portal/guests_spec.rb`, `spec/requests/public/payments_spec.rb`, `spec/requests/public/pre_checkins_spec.rb`, `spec/requests/public/concierge/check_ins_spec.rb`
- [ ] **Deferred to Phase 3:** the guest/public-facing e-invoice specs (`spec/requests/guest/bookings_e_invoice_spec.rb`, `bookings_e_invoice_request_spec.rb`, `bookings_e_invoice_status_spec.rb`, `spec/requests/public/bookings_e_invoice_spec.rb`, `bookings_e_invoice_status_spec.rb`, `spec/requests/public/bookings_show_spec.rb`) assert on rendered markup from the request modal and booking-show views, which don't exist until Phase 3d. Do not run them here — they will fail for reasons unrelated to Phase 2.

---

## Phase 3 — Rebuild UI against the new Booking Control Panel / Settings architecture (highest effort)

This is not a merge job — these are net-new UI surfaces to build against `main`'s current patterns, using the old branch's views as a functional spec for what each screen needs to do, not as source to copy in.

### 3a. Hotel-portal: "Issue e-Invoice" folio/document action
Old branch touched `app/views/hotel_portal/folios/show/_folio_actions.html.erb` and `app/views/hotel_portal/bookings/show/_documents_actions.html.erb` — both deleted on `main`.
- [ ] Identify correct new home: likely `app/views/hotel_portal/bookings/workspaces/folio_operations/_folio_actions.html.erb` and/or `app/views/hotel_portal/bookings/actions/documents/show.html.erb` (backed by `app/controllers/hotel_portal/bookings/actions/documents_controller.rb`)
- [ ] Add "Issue e-Invoice" / "View e-Invoice status" action following the existing `PanelsUI::Button` + `data: { turbo_frame: "folio_action_sheet" }` action-sheet pattern already used in `_folio_actions.html.erb` (see e.g. the "Add Payment" button block for the pattern to copy)
- [ ] Wire status badge — port `app/views/hotel_portal/e_invoice_submissions/_status_badge.html.erb` (new file, no conflict) and render it in the workspace documents panel (`app/views/hotel_portal/bookings/workspaces/documents/_panel.html.erb`)
- [ ] Confirm `HotelPortal::Bookings::WorkspacePresenter` (used by `DocumentsController#show`) is the right place to expose e-invoice status/eligibility to the view, rather than querying the model directly in the template

### 3b. Hotel-portal: e-invoice submissions index/show pages
- [ ] Port `app/views/hotel_portal/e_invoice_submissions/index.html.erb` and `show.html.erb` as new files (no upstream conflict) — check they use current `PanelsUI` components (`PanelsUI::PageHeader`, `PanelsUI::Tabs`, `PanelsUI::Button`, etc.) consistently with sibling pages built after divergence, not the older component API
- [ ] **Per memory:** use the `cached_icon` helper for any icons in these views — do not hand-write inline `<svg>`

### 3c. Hotel-portal: settings — e-invoice section
Old branch added a standalone settings tab (`_e_invoice_section.html.erb`, edited `_settings_tabs.html.erb` which no longer exists). Current `main`'s settings system is page/presenter-driven:
- [ ] Add `"e_invoice"` to `HotelPortal::SettingsController::SETTINGS_PAGES` (`app/controllers/hotel_portal/settings_controller.rb`)
- [ ] **Decide the settings group first — it determines the URL.** `finance` and `commercial` are the candidates (e-invoice is a billing concern). Ask the user; **default to `finance`** if running unattended, since that group already holds `banking-details` and taxes. Record the choice before writing the route.
- [ ] Add the route **nested inside the chosen group's sub-scope**, not flat under `scope "settings"`. Copy the shape of the existing `banking-details` route (`config/routes.rb` ~line 646), which lives inside `scope "finance" do ... end`:
  ```ruby
  scope "finance" do
    # ...existing routes...
    get "e-invoice", to: "settings#index", as: :e_invoice_settings, defaults: { settings_page: "e_invoice" }
    patch "e-invoice", to: "settings#update", defaults: { settings_page: "e_invoice" }
  end
  ```
  A flat route would yield `/hotel/:id/settings/e-invoice` and break the group-tab navigation, which derives the active group from the URL segment.
- [ ] Add `"e_invoice"` case to `SettingsController#settings_page_path`, and register the page in `SETTINGS_GROUPS` in `app/helpers/hotel_portal/settings_navigation_helper.rb` (this is where `SETTINGS_GROUPS`, `settings_tabs_for_group`, and `settings_group_active?` actually live — **not** in `SettingsPresenter`, which is at `app/presenters/hotel_portal/settings_presenter.rb`)
- [ ] Add `"e_invoice"` to `permitted_settings_pages` in `SettingsController` under the appropriate permission check (`manage_hotel_profile` vs `manage_account`) — without this the page 404s/redirects even with the route in place
- [ ] Port `app/views/hotel_portal/settings/_e_invoice_section.html.erb` as a new partial, update it to match current settings partial conventions (compare against `_banking_section.html.erb` or `_general_section.html.erb` for the current structural pattern)
- [ ] Add rendering branch in `app/views/hotel_portal/settings/index.html.erb`'s `case @presenter.active_page` block
- [ ] Add a form object if settings save logic needs one, following `HotelPortal::GeneralSettingsForm` / `HotelPortal::BankingDetailsForm` conventions already used by `SettingsController#update`

### 3d. Guest portal: e-invoice request flow
Guest-side views were not restructured — this should be the easiest UI piece.
- [ ] Port `app/services/e_invoice` guest touchpoints already done in Phase 1/2
- [ ] Reapply diff to `app/views/guest/bookings/show.html.erb` (82-line addition) by hand against current version
- [ ] Port `app/views/shared/_e_invoice_request_modal.html.erb` and `app/javascript/controllers/e_invoice_request_modal_controller.js` as new files
- [ ] Reapply diff to `app/views/public/bookings/show.html.erb` (64 lines), `app/views/public/quotes/show.html.erb`, `app/views/public/pre_checkins/show.html.erb`, `app/views/public/concierge/check_ins/check_in_now.html.erb` and `check_in_now_mobile.html.erb` by hand
- [ ] Register `app/javascript/controllers/e_invoice_settings_controller.js` in the Stimulus importmap/controllers index if not auto-registered

### Phase 3 verification
- [ ] Manually click through: guest requests an e-invoice from booking show page → status updates → hotel staff sees submission in `hotel_portal/e_invoice_submissions` → staff can view/download from folio action → settings page shows and saves e-invoice config
- [ ] Run the guest/public specs deferred from Phase 2: `spec/requests/guest/bookings_e_invoice_spec.rb`, `bookings_e_invoice_request_spec.rb`, `bookings_e_invoice_status_spec.rb`, `spec/requests/public/bookings_e_invoice_spec.rb`, `bookings_e_invoice_status_spec.rb`, `spec/requests/public/bookings_show_spec.rb`
- [ ] Run the full `spec/requests/hotel_portal/e_invoice_submissions_spec.rb` (570-line suite) now that the views exist
- [ ] Port the additive diff to `spec/models/booking_spec.rb` (the stale branch's version is heavily diverged — apply only the e-invoice `describe` blocks, don't replace the file)
- [ ] **Write a new spec** for the e-invoice action added in 3a. The stale branch's `spec/requests/hotel_portal/bookings/show_actions_spec.rb` targets a controller deleted on `main` and has no valid destination — do not port it. Follow the current convention instead: `spec/requests/hotel_portal/bookings/actions/*_spec.rb` (see `no_shows_spec.rb` for the established shape).
- [ ] Visual check in browser (per project convention: don't claim UI success without actually running it) — use `/run` skill or manually boot the app and exercise the golden path

---

## Phase 4 — Full regression + schema reconciliation

- [ ] `bin/rails db:migrate` cleanly from a fresh schema load; `db/schema.rb` diff should be additive-only (no unrelated column changes bleeding in from the stale branch)
- [ ] Full spec suite: `bin/rspec`
- [ ] `bin/rubocop`
- [ ] `bin/brakeman` (new external API client code — `my_invois/client.rb` — warrants a security pass: check for SSRF/credential-leak issues in the HTTP client and token store)
- [ ] Re-run the "Real-world scenario QA" checklist from `docs/e-invoice-update-plan.md` (payment-concluded issuance, same-month guest request, <RM10k consolidation, ≥RM10k individual-only, adjustment notes) against the integrated code — these were flagged incomplete in the original branch's own plan doc and nothing in this integration exercises new logic that would resolve them
- [ ] Confirm `MonthlyConsolidationJob` is actually registered in the deployed Solid Queue recurring config for the target environment, not just present in `config/recurring.yml`

---

## Phase 5 — Rollout readiness (product/ops sign-off, not code)

Carried over from the original branch's own unresolved sign-off list — still open, still blocking a real launch regardless of this integration:
- [ ] Confirm with product: should hotel staff get a manual "issue on behalf of guest" action for low-value bookings?
- [ ] Confirm with product: should adjustment-note PDFs show `Original Total + Adjustment = Revised Total` for readability?
- [ ] Confirm with product: should guest/public portals expose adjustment-note downloads, or only the original invoice?
- [ ] Confirm ops playbook exists for month-end consolidation batch failures
- [ ] Confirm MyInvois production credentials are provisioned and `my_invois/client_factory.rb` picks the right client (mock vs real) per environment
