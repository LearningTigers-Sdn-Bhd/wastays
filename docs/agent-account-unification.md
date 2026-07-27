# Agent Account Unification — Progress Tracker

Merges `AgentAccount` (code-lookup, no login) into `HotelCorporateAccount`
(email-invited, portal login, full AR wiring) so travel agents/airlines get
real billing, invoicing, statements, and a login-capable portal, while
keeping the "enter agent code at checkout" booking-time UX.

Key decision (confirmed): **link/merge into `HotelCorporateAccount`**, not a
separate parallel model. "No-show / disputed charges" is a folio charge
category, unrelated to this account-type decision.

~~Open item: `bookings.corporate_entity_id` / `CorporateEntity`~~ — **resolved,
not applicable**. Verified there is no `corporate_entities` table, model, or
any reference anywhere in the current schema/codebase/git history. It doesn't
exist. Nothing to reconcile before Phase 1.

---

## Phase 1 — Merge AgentAccount into HotelCorporateAccount (foundational)

Status: **Done** (2026-07-13)

- [x] `HotelCorporateAccount`: add `airline` to `ACCOUNT_TYPES`; DB check constraint `hotel_corporate_accounts_account_type_allowed` updated too
- [x] `HotelCorporateAccount`: `UNAVAILABLE_ACCOUNT_TYPES` emptied (was `[travel_agent]`)
- [x] `HotelCorporateAccount`: added `agent_code`, `contact_email`, `contact_phone` columns (migration `20260713100101`), `agent_code` unique scoped to `hotel_id`, 6-char generator ported from `AgentAccount`, runs `before_validation on: :create` for every account type (not just agents)
- [x] `BookingBillingParty`: `airline` added to `ACCOUNT_TYPES`, `UNAVAILABLE_ACCOUNT_TYPES` emptied
- [x] `_party_list.html.erb`: "(coming soon)" auto-resolved (reads `UNAVAILABLE_ACCOUNT_TYPES` dynamically); uses the unified "Corporate account" label
- [x] Data migration `20260713100102`: for each `AgentAccount` → `Account`(corporate) + `HotelCorporateAccount` carrying `account_type`, `agent_code`, `contact_email`, `contact_phone` (0 rows existed in dev DB, logic verified by code path)
- [x] Renamed `bookings.agent_account_id` / `booking_quotes.agent_account_id` → `hotel_corporate_account_id`, backfilled in the same migration, old FK/column/table dropped
- [x] Retired `AgentAccount` model, `agent_accounts` table, `hotel_portal/agent_accounts_controller.rb` + views + helper, `agent_account_policy.rb`, route, specs (model/request/view specs deleted; system spec + factory usage updated to `hotel_corporate_account`)

**Note:** because the schema rename lands in this same phase, most of Phase 2's *plumbing* (session key, controller/service param renames, model associations) had to move into Phase 1 to keep the app bootable — see checked items below. Only the genuinely new *behavior* (auto-creating `BookingBillingParty` on confirm) remains in Phase 2.

Verification: `bin/rubocop` clean on all touched files; `bundle exec rspec spec/system/public/booking_features_spec.rb spec/models/booking_spec.rb spec/models/hotel_corporate_account_spec.rb spec/models/booking_billing_party_spec.rb spec/services/booking_engine/ spec/requests/public/` → 221 examples, 0 failures (1 pre-existing unrelated pending).

## Phase 2 — Booking-time wiring

Status: **Done** (2026-07-13)

- [x] `Public::HotelsController#set_agent_account`: lookup via `hotel.hotel_corporate_accounts.active.find_by(agent_code:)`
- [x] Renamed `session[:agent_account_id]` → `session[:hotel_corporate_account_id]`
- [x] `ApplicationController#current_agent_account`: repointed to `HotelCorporateAccount`
- [x] `BookingEngine::CreateQuote`, `BookingEngine::ConfirmBooking`, `Booking`: swapped `agent_account_id`/`belongs_to :agent_account` → `hotel_corporate_account_id`/`belongs_to :hotel_corporate_account`; `Public::QuotesController` params renamed too
- [x] `BookingEngine::AvailabilityService`: unaffected — keys off boolean `corporate_rate` param, not the id, no change needed
- [x] `Folios::InitializeForBooking#create_folio!`: when `booking.hotel_corporate_account_id` is present and the account is `active?`, auto-creates/reuses a `BookingBillingParty` (`party_kind: "company"`) and makes the **primary folio itself** `folio_type: "external"`, `payer_type: "company"` — not a second folio, since `Folios::ResolveTargetFolio`'s no-routing-rule fallback always targets `booking.booking_folio` (the primary), so a second folio wouldn't receive nightly charges without also configuring a `FolioRoutingRule` (a separate manual staff feature, out of scope here). Falls back to the normal guest folio if the linked account is suspended.
  - Confirmed this composes correctly with existing checkout logic in `Folios::CloseForCheckout#valid_direct_bill_close?`: whether checkout can close with an outstanding balance depends on the account's `direct_bill_enabled` flag (already exists, defaults false) — maps directly onto "local agents pay at confirmation, international agents pay net-30" from the spec, no further code needed for that distinction.
  - Design decision confirmed with user: **auto** rather than manual-only, since local agents expect billing to just work.
  - Tests: 2 new specs in `spec/services/folios/initialize_for_booking_spec.rb` (happy path + suspended-account fallback). Full run: `spec/services/folios/ spec/services/booking_engine/confirm_booking_spec.rb spec/system/public/booking_features_spec.rb` → 287 examples, 0 failures.

## Phase 3 — "Register Agent" UI (hotel_portal)

Status: **Done** (2026-07-13)

- [x] `CorporateInvitation`: added `account_type` to metadata store_accessor, validated inclusion in `HotelCorporateAccount::ACCOUNT_TYPES`, defaults to `"company"`
- [x] `CorporateInvitations::CreateService` / `AcceptService`: carry `account_type` through from invitation → `HotelCorporateAccount`
- [x] `hotel_portal/corporate_accounts_controller.rb`: `create` permits `account_type`
- [x] `corporate_accounts/new.html.erb`: added an account type `<select>` to the single "Invite Corporate Account" form — no separate "Register Agent" entry point; a `?account_type=`-driven header/pre-select and a second "Register Agent" button were tried and then removed as redundant (one form with a type dropdown covers both, per user feedback)
- [x] `corporate_accounts/index.html.erb`: single "Invite Corporate Account" button; table shows account type + `agent_code` per row, and pending invitations show their account type
- [x] Standardized `CreateService`/`AcceptService` user-facing error messages on "Corporate Account", since the flow serves all four account types
- [x] Tests: 3 new specs (`create_service_spec.rb` account_type default/passthrough, `accept_service_spec.rb` account_type + agent_code generation on acceptance). Full run: `spec/services/corporate_invitations/ spec/models/corporate_invitation_spec.rb spec/requests/hotel_portal/corporate_accounts_spec.rb` → 29 examples, 0 failures. `new`/`index` view rendering already covered by existing request specs.

## Phase 4 — Dashboard / Invoice / SOA / Aging

Status: **Done** (2026-07-13)

- [x] QA finding: `Folios::CloseForCheckout` was already fully account_type-agnostic and already checked `direct_bill_enabled?` correctly (via `Checkouts::SheetPresenter#direct_bill_enabled?`) — no code changes needed here, this phase was pure verification.
- [x] `spec/integration/agent_billing_pipeline_spec.rb` (new): two bookings under one agent → both fold into `company`-payer folios sharing the same `hotel_corporate_account` (separate `BookingBillingParty` rows, since that association `belongs_to :booking`) → posted nightly charges → `Folios::CloseForCheckout` with `direct_bill_folio_ids` creates an `ArInvoice` per booking, correctly attributed and due-dated off `payment_terms_days` → `ArInvoices::AgingReport` aggregates both under the one agent row → `Reports::AccountsReceivable::GenerateStatementRecords` lists both invoices on the agent's statement. Also confirms checkout correctly *refuses* to close with a balance when direct billing isn't explicitly selected at checkout (matches the deliberately manual, staff-controlled checkout-sheet pattern).
- [x] `spec/requests/corporate_portal/agent_billing_visibility_spec.rb` (new): an agent's `corporate_portal` login (a `travel_agent`-typed `HotelCorporateAccount`) sees the resulting outstanding balance on `corporate_dashboard_path` and the invoice on `corporate_ar_invoices_path` — confirmed `corporate_portal/base_controller.rb` has zero `account_type` gating, so this "just worked" once Phases 1-3 landed.
- [x] Confirmed `ArInvoices::AgingReport`/`GenerateStatementRecords`/dashboard are entirely generic over `hotel_corporate_account` — no account_type branching anywhere in those read paths, so no separate coverage was needed beyond proving the new agent-originated data flows through correctly (PDF rendering itself — `ar_statements_controller`'s `Reports::AccountsReceivable::GenerateStatement` Prawn output — was not visually inspected, only the underlying `GenerateStatementRecords` data it renders from).
- [x] Full run: `spec/integration/ spec/services/folios/ spec/services/corporate_invitations/ spec/requests/corporate_portal/ spec/requests/hotel_portal/corporate_accounts_spec.rb spec/services/ar_invoices/ spec/services/reports/accounts_receivable/` → 361 examples, 0 failures

## Phase 5 — Payment slip upload + admin verification (net-new)

Status: **Done** (2026-07-14)

- [x] New `ArPaymentSubmission` model (migration `20260714000655`): `hotel_id`, `hotel_corporate_account_id`, `submitted_by` (User), `amount`, `currency`, `reference_number`, `received_at`, `payment_method`, `notes`, `status` (pending/approved/rejected, DB check constraint), `rejection_reason`, `ar_payment_id` (nullable FK, set on approval), `reviewed_by`/`reviewed_at`. `has_one_attached :slip`, required on create.
- [x] `corporate_portal/ar_payment_submissions_controller` (index/new/create) — agent uploads slip + amount/reference/method, scoped to their own linked `hotel_corporate_accounts`; added "Submit Payment" to the corporate sidebar nav under Finance.
- [x] `hotel_portal/ar_payment_submissions_controller` (index/show/reject) — **no separate "approve" action**: `show` links to the *existing* `hotel_portal/ar_payments#new` form (already supports prefill via `params.dig(:ar_payment, ...)`), passing `ar_payment_submission_id` through. `ar_payments_controller#new`/`#create` were extended to look up that submission, prefill the form (`_payment_fields.html.erb` falls back to the submission's values), and on successful `ArPayments::RecordPayment`, call `submission.approve!(ar_payment:, reviewed_by:)`. This reuses 100% of the existing payment-recording/allocation logic — no duplicated validation. Added "Payment Submissions" to the hotel_portal AR nav.
- [x] Tests: `spec/models/ar_payment_submission_spec.rb` (4 examples: slip required, hotel mismatch validation, approve!/reject! stamping), `spec/requests/corporate_portal/ar_payment_submissions_spec.rb` (3: scoping, submit with attached slip, rejects mismatched hotel), `spec/requests/hotel_portal/ar_payment_submissions_spec.rb` (6: scoping, show with slip link, prefilled `new`, full approve-via-create round trip linking the real `ArPayment`, reject with reason, permission gate). Full run incl. existing `ar_payments` specs: 65 examples, 0 failures.

## Phase 6 — Reporting

Status: **Done** (2026-07-14)

- [x] `HotelPortal::Reports::DailyRevenueReport`: added an `ar_bank_transfer` bucket sourced from `ArPayment.where(hotel_id:, payment_method: "bank_transfer", received_at: range)`, grouped by `received_at` date, folded into `total_payments`/`net_amount` for both daily rows and monthly rollups. **Not** added to `source_rows` — an `ArPayment` isn't attributable to a single booking's channel/source the way `FolioTransaction`s are, so forcing it into that breakdown would misattribute revenue; it only appears in the top-level daily/totals view.
  - Updated all 4 surfaces consistently: HTML table (new "Agent Transfer" column), CSV export, Excel export, PDF export (`Date/Bkgs/Accom/Other/Tax/Charges/Disc/Online/Cash/Deposit/Agent/Refund/Net`).
  - Tests: new spec in `daily_revenue_report_spec.rb` (in-range/out-of-range/wrong-method/wrong-hotel isolation), updated CSV export spec's header/row assertions. Full run: `spec/services/hotel_portal/reports/ spec/services/ar_invoices/ spec/requests/hotel_portal/ar_invoices_spec.rb spec/requests/hotel_portal/reports_spec.rb` → 175 examples, 0 failures.
- [x] New "Agent Summary Statement" — `hotel_portal/ar_invoices#agent_summary` (route `/hotel/:id/accounts-receivable/agent-summary`), reusing `ArInvoices::AgingReport` (which already aggregates every corporate account hotel-wide with aging buckets) rather than building a new aggregation from scratch. Added an optional `account_types:` filter to that service (`%w[travel_agent airline]` here), and reused the existing `AgingPresenter` + `_metrics`/`_table` partials unchanged since they're already account_type-agnostic. New `Reports::AccountsReceivable::GenerateAgentSummary` Prawn service for the printable PDF (mirrors the `DailyRevenuePdfExportService`'s simple-table style, not the heavier per-account `GenerateStatement` ledger, since this is a cross-account summary, not one account's transaction history). Added "Agent Summary" to the hotel_portal AR nav.
  - Tests: `aging_report_spec.rb` (+1: account_types filtering), `ar_invoices_spec.rb` (+2: HTML scoping to travel_agent/airline only, PDF export renders). Included in the 175-example run above.

## Phase 7 — Agent self-service booking panel (later, separate effort)

Status: **Not started**

- [ ] New booking UI inside `corporate_portal`, reusing `Public::QuotesController` / `BookingEngine::CreateQuote` under the hood, authenticated as the agent's `User`
- [ ] Guest-name entry synced to owner's PMS
