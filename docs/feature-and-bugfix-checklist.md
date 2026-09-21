# Checklist: TA payments, attribution, Chinese, and four fixes

**Status (18 Sep 2026).** The four bugs, the agent attribution (item 2) and the
TA payment deadline (item 1) are built on `plan/ta-payments-and-localisation`.
Still outstanding: the Chinese version (item 3) and the reminder emails (§5).
Ticked boxes below are done and specced; unticked ones are not.

> **None of it is committed.** It is all in the working tree on
> `plan/ta-payments-and-localisation` (last commit `1bf4c2f44`): ~66 changed and
> new paths, four migrations, and the hand-edited `db/schema.rb`. Read
> "Before touching anything" below before you run `db:migrate` or `git add`.
>
> The dev **and** test databases already have all four migrations applied.

### Four migrations were added

| Migration | What it adds |
| --- | --- |
| `20260918013335_add_corporate_booked_by_to_bookings` | `bookings.corporate_booked_by_id`, `bookings.corporate_booked_at` |
| `20260918015110_seed_travel_agent_booking_source` | re-runs `BookingSource.seed_defaults!` so existing databases pick up `travel_agent` |
| `20260918015546_add_agent_payment_hold_to_bookings_and_accounts` | `hotels.agent_payment_hold_hours` (default 48), `hotel_corporate_accounts.agent_payment_hold_hours` (nullable override), `bookings.payment_due_at` |
| `20260918015602_add_booking_to_ar_payment_submissions` | `ar_payment_submissions.booking_id` — see the note under item 1 |

### Where the new code lives

- `app/models/bookings/payment_hold.rb` — the one place that decides a deadline.
- `app/services/bookings/release_unpaid_agent_bookings.rb` + `app/jobs/bookings/release_unpaid_agent_bookings_job.rb`
  — the sweeper, scheduled every 5 minutes in `config/recurring.yml`.
- `app/presenters/corporate_portal/booking_payment_presenter.rb` and
  `app/views/corporate_portal/bookings/_payment_deadline.html.erb` — the TA-facing
  deadline, amount and countdown.
- `app/javascript/controllers/payment_deadline_controller.js` — deliberately **not**
  the existing `countdown_controller.js`, which counts minutes and reloads the page.
- `app/models/rooms/status_presentation.rb` — now the only room-status colour **and**
  icon map; StayView's private copy is gone.
- `app/views/hotel_portal/bookings/_agent_badge.html.erb`,
  `app/views/hotel_portal/ar_payment_submissions/_slip.html.erb`,
  `app/views/corporate_portal/ar_payments/_gateway_option.html.erb` — shared partials.

### Verification at handoff

`bundle exec rspec --exclude-pattern "spec/system/**/*"` → **9,613 examples, 1
failure**, that one being the pre-existing `panels_ui/table_spec.rb:69` (fails on
clean `HEAD` too). Rubocop clean; Brakeman 0 warnings. System specs were not run.

Read [ta-payments-and-localisation.md](ta-payments-and-localisation.md) for the
reasoning behind each decision. This file is the checklist and the traps.

---

## Before touching anything

- [ ] **`db/schema.rb` in this working copy carries drift from other branches.**
      It currently shows ~80 insertions that are not yours: `deposit_percentage_override`,
      `group_booking_deposit_percentage`, `group_booking_request_hold_hours`,
      precision changes on `ota_rate_variance_policies`, and a *dropped*
      `concierge_booking_verifications` table. Committing the generated file
      reverts another branch's table.
      **Always** `git checkout HEAD -- db/schema.rb` and re-insert only your own
      table and foreign keys by hand before committing a migration.
      This branch's `db/schema.rb` diff should be exactly **5 added lines plus the
      version bump** — `git diff --numstat db/schema.rb` reports `14  1`
      (14 added, 1 removed). Anything larger means the generated file leaked back in.
- [ ] **Restart the server after any Gemfile change.** Bundler locks the bundle
      at boot; a long-lived Puma keeps whatever it started with. A `LoadError`
      for a gem that is plainly in the Gemfile means a stale process, not a bad
      branch.
- [ ] Run the full suite before claiming done. There is a coverage gate
      (`spec/services/service_spec_coverage_spec.rb`) requiring one spec file per
      `app/services` file; new services fail CI without one.
      Two known non-issues when reading a red run:
      `spec/components/panels_ui/table_spec.rb:69` fails on clean `HEAD` too, and
      running two rspec processes at once produces spurious
      `pg_advisory_xact_lock` failures across unrelated files.
- [ ] **`db:migrate` rewrites `db/schema.rb` every time**, re-introducing the
      drift above — including the test-env migrate. Re-apply the hand edits after
      *each* run, not just the last one, and check `git diff --numstat db/schema.rb`
      before committing.

---

## Bugs (item 4) — smallest, do first

### [x] i. StayView booking uses 00:00 instead of the hotel's hours

`Bookings::ScheduledStay.at_hotel_time` is **correct** and should not be
changed. It applies the property policy time only when handed a *date-only*
value; anything matching `\d[T ]\d` is parsed literally. So a caller is sending
`2026-09-20 00:00` and getting exactly that.

**What it actually was.** The caller *was* sending a date. `hotel.bookings.build(check_in: ...)`
assigns the attributes *before* the association sets the owner, so `Booking#check_in=`
ran with `hotel` still nil, skipped `at_hotel_time` entirely and let Rails cast the
bare date to midnight UTC. Nothing was wrong with `ScheduledStay`.

Fixed in two places: `Booking` re-applies the policy in a `before_validation`
(covering every creation path, including `BookingEngine::ConfirmGroupBooking`,
which had the same latent bug), and the Sheet controller assigns the hotel first
so the *rendered form* is right before validation ever runs.

### [x] ii. Payment proof not visible to hotel admin

**Reproduce before scoping. The reported symptom does not match the code.**

In `app/views/hotel_portal/ar_payment_submissions/show.html.erb` the slip link
renders **unguarded**: `rails_blob_path(@submission.slip, …)` with no
`attached?` check. An unattached slip would *raise*, not render nothing. So
either that is not the screen in question ("Financials → Payment Record"), or
the attachment never arrives.

**What it actually was.** Slips attach fine — every submission in dev had one. The
gap was reachability. The hotel admin approves or rejects on
`ar_payments#new?ar_payment_submission_id=`, which showed no slip at all, so the
decision was made blind; and `ArPayment` had no inverse association, so once
approved the proof was unreachable from the payment forever.

Fixed: `ArPayment has_one :ar_payment_submission`, a shared `_slip` partial on all
three screens (review, submission, approved payment), and the unguarded
`rails_blob_path` now says "No slip on file" instead of raising.

### [x] iii. Remove card payment for TAs, bank transfer only

- `app/views/corporate_portal/ar_payments/choose_method.html.erb` offers a
  Razorpay card path beside the submission route.
- Decide: remove the option for TAs only, or disable the gateway path entirely.
- Check for in-flight card payments before removing the route.

**What was decided.** TAs only, keyed on `account_type == "travel_agent"` via the
new `HotelCorporateAccount#gateway_payments_allowed?`. Other corporate types keep
the gateway. There were **zero** in-flight intents (`CorporateArPaymentIntent.count`
was 0), so nothing had to be drained first.

Enforced in two places, because hiding the tile is not enough — a TA could still
POST to `review`: the card tile is not rendered at all (not merely disabled, since
there is nothing the agent could do to enable it), **and**
`CorporateArPayments::CreateIntent` refuses with "Travel agent accounts settle by
bank transfer."

### [x] iv. Colour-code housekeeping room status

**There are seven statuses, not three**, and the clean one is `ready`:

`ready`, `dirty`, `cleaning`, `awaiting_inspection`, `inspection_failed`,
`out_of_service`, `late_checkout_detected` (`RoomStatus::STATUSES`).

- Seven states cannot be separated by hue alone, and colour alone fails
  colourblind users. Give each a colour **and** an icon or shape.
- Apply the same pair in the housekeeping page, StayView and the room cards —
  one status must not look different in two places.
- `RoomStatus::ASSIGNABLE_STATUSES` is `["ready"]` only; that distinction is
  worth showing.

**What was found.** The "two places" problem was already real and worse than
described: `Rooms::StatusPresentation` held the shared colours, but
`HotelPortal::StayView::RoomSummary` carried its **own private `STATUS_ICONS`**
with different icons — and no entry for `late_checkout_detected` or `occupied`,
so both rendered as a "?" . The status-guide legend listed only six of the seven.

Three pairs share a badge variant and so cannot be told apart by colour at all:
`cleaning`/`awaiting_inspection` (`:info`), `inspection_failed`/`out_of_service`
(`:destructive`), `dirty`/`late_checkout_detected` (`:warning`). The icon is what
separates them, and a spec now asserts that every same-variant pair has distinct
icons.

Fixed: icons moved into `Rooms::StatusPresentation` as the single source, the
housekeeping board badge gained the icon, and `StatusGuide::ROOM_STATUS_ENTRIES`
is now derived from `RoomStatus::STATUSES` so a new status cannot ship without a
line in the legend. `StatusPresentation.assignable?` exposes the `ready`-only
distinction.

---

## Feature: TA payment deadline that releases rooms (item 1)

Settled: **standard (non-direct-bill) accounts only**; **the clock stops when
payment proof is uploaded**, not when approved, and resumes only on rejection.

### Traps that decide the design

- [x] **Do not hold the booking in `pending`.** Availability counts only
      `confirmed`, `no_show_detected`, `checked_in`, `due_out_detected`,
      `checkout_required` — in both `Bookings::AvailableRoomNumbers` and
      `CorporatePortal::AgentStaySearch`. A `pending` booking blocks nothing, so
      **the room would be sold twice.** Create it `confirmed` and carry a
      deadline.
- [x] **Do not reuse `hotel_corporate_accounts.payment_terms_days.`** That is
      when an AR invoice falls due. Sharing it makes an invoice-terms change
      silently move inventory. Add a separate attribute plus a hotel default.
- [ ] **`hotels.group_booking_request_hold_hours`** — still open, deliberately.
      It is in the *local database* (another branch's migration was run here) but
      **not in this branch's `db/schema.rb`**, so building on it would break a
      fresh `db:schema:load`. This branch adds its own
      `hotels.agent_payment_hold_hours` / `hotel_corporate_accounts.agent_payment_hold_hours`
      instead. **Reconcile the two when that branch merges** — one of them should go.
- [x] **Use wall-clock time, not the business date.** The business date only
      moves when the night audit runs and can sit days behind; a deadline is a
      promise to an agent. Say so in the code.
- [x] **Floor the deadline at arrival.** A booking made for tomorrow cannot wait
      three days. The UI has to explain this.
- [x] State the timezone on screen — the agent may not be in the hotel's.

### To build

- [x] Deadline setting on the relationship + hotel-level default, admin-editable.
- [x] `payment_due_at` on the booking, stamped at creation.
- [x] Sweeper job: cancel expired, unpaid, unprotected bookings. Idempotent, and
      **it must log every release** — an automated cancellation nobody can audit
      is not acceptable in a money path.
- [x] Sweeper skips any booking with an `ArPaymentSubmission` awaiting review.
- [x] **Pay now** in the TA portal: amount, deadline, countdown, on the list and
      the booking.

### The decision this feature forced

**A standard TA has nothing to pay against.** `ArInvoice` records are raised from
a *closed folio at checkout* (`Folios::Lifecycle::CreateDirectBillArInvoice`), and
only for direct-bill accounts. So at booking time — exactly when the deadline is
running — a standard agent has no invoice, and `ArPaymentSubmission` could only
ever target invoices.

Resolved by giving `ar_payment_submissions` an optional `booking_id`: a submission
now settles invoices (allocations, as before) **or** prepays a booking. The
`has_at_least_one_allocation` validation became `has_a_target` ("at least one
outstanding invoice or a booking"), plus `booking_matches_relationship` so a
submission cannot name another account's booking.

This reuses the existing review/approve/reject flow rather than adding a second
one — which is why bug ii's slip work matters here too. **It is the largest
extension in this branch and the piece most worth reviewing.**

### How the clock actually stops and restarts

- Uploading a slip does **not** change `payment_due_at`. The sweeper simply skips
  any booking with a `pending` submission (`protected_by_submission?`). The agent
  is never punished for the hotel's review queue.
- `approve!` clears `payment_due_at` — the rooms are paid for.
- `reject!` **extends** `payment_due_at` by `reviewed_at - created_at`, giving back
  exactly the time the review took, still floored at arrival.
- A rejected submission stops protecting the booking, so the clock resumes.

### Not done here

- Nothing **backfills** `payment_due_at` for agent bookings that already exist.
  They simply have no deadline and are never swept. Decide whether that is right
  before going live.
- The sweeper cancels; it does not notify. That is §5.

---

## Feature: mark a reservation as the agent's (item 2)

Half done already — `CorporatePortal::CreateAgentBooking` sets
`hotel_corporate_account_id`, so the booking knows the agency.

- [x] **`source` is `"internal"`**, same as a staff-keyed booking, so agent
      bookings are invisible in any source-grouped report. `BookingSource` has no
      agent key; adding one is a registry change affecting every hotel.
      **Decided (client): add it as a selectable `manual` source.** `travel_agent`
      / "Travel Agent" now sits in `DEFAULT_SOURCES`, and `CreateAgentBooking`
      writes `source: "travel_agent"`. Being `kind: "manual"` it also appears in
      **every hotel's** staff source dropdown on purpose, so a booking an agent
      phoned or emailed in can be tagged the same way — with the accepted
      trade-off that staff can mis-select it.
      Existing agent bookings keep `source: "internal"`; there is **no backfill**.
- [x] **The acting person is not recorded.** Capture which corporate user made
      it — cheap now, painful to backfill.
- [x] Badge on the reservation and the booking workspace: agency, person, time.
      One shared partial (`hotel_portal/bookings/_agent_badge`) reads an
      `agent_attribution` hash, so `WorkspacePresenter` and
      `HotelPortal::BookingPresenter` both satisfy it. The badge shows only when
      `corporate_booked_at` is present, so pre-existing corporate bookings stay
      unmarked rather than claiming an author nobody recorded.

---

## Feature: Chinese version (item 3)

Scope settled: **TA portal first**, guest-facing soon, hotel portal and admin
eventually — so the architecture must scale to all of it.

### The finding that reshapes this

**There is no i18n layer.** 37 `t()` calls across **867** ERB templates, and a
31-line `en.yml`. The provider is the small part; extraction is the job.

| Surface | Templates |
| --- | --- |
| Corporate (TA) portal | **29** ← first slice |
| Guest portal | 7 |
| Public (booking, concierge, GRC) | 49 |
| Admin | 76 |
| Hotel portal | **553** |
| Shared components | 54 |

### Traps

- [ ] **Do not translate rendered HTML.** It cannot tell chrome from data and
      would translate guest names, hotel names, addresses and amounts. Extract
      keys instead.
- [ ] **The Great Firewall does not constrain the provider.** Server-side
      translation cached in the database is called from our server, not the
      guest's browser. It would only matter for a client-side widget. Pick on
      quality/cost/correctability: DeepL (best zh), self-hosted LibreTranslate
      (free, we own it), Azure (has a China region).
- [ ] **Our own asset delivery is the real China question** — fonts, CDN,
      third-party scripts. Separate work; check before claiming the site works
      there.
- [ ] **Human corrections must permanently outrank machine output.** A
      re-translation must never overwrite a corrected string.
- [ ] **Human-translate financial, legal and tax strings from the start** —
      e-invoice terms, "non-refundable", "credit limit", tourism tax. Machine
      translation for the long tail only.
- [ ] Put the provider behind an adapter; it will change, the cache must survive.

### To build

- [ ] Translation store in the database, keyed by locale + key, with a
      `corrected` flag and a `never_translate` flag.
- [ ] Per-page, on-demand population rather than whole-catalogue loading.
- [ ] Superadmin screen: review, correct, search, lock.
- [ ] Extract the 29 corporate-portal templates as the first slice, and treat it
      as the architecture test before the 553.

### Open questions for the client

- Simplified or Traditional? (Not interchangeable — mainland vs Taiwan/HK.)
- Do dates, currency and number formats localise, or only words?
- Language chosen per account or per session?

---

## Feature: payment reminder emails (§5 of the plan)

**Now unblocked** — item 1 is built, so the deadline these remind about exists.
The hooks to attach to:

- `bookings.payment_due_at` is the date to count back from (wall-clock).
- `Bookings::ReleaseUnpaidAgentBookings` is the sweeper; a reminder job should
  read the same scope (`confirmed`, unpaid, `payment_due_at` set, corporate) but
  **must not** reuse the sweeper's "skip" logic verbatim — a booking protected by
  a pending submission needs no reminder either, which is the same predicate
  (`ArPaymentSubmission.pending.for_booking`).
- `ArPaymentSubmission#approve!` / `#reject!` are where the accept/reject
  notifications belong. `reject!` already extends the deadline, so the rejection
  email can state the **new** `payment_due_at` rather than a stale one.
- `booking.corporate_booked_by` gives the person to email, and
  `hotel_corporate_account.effective_contact_email` the account-level fallback.

- [ ] Reuse `notification_configs` (per hotel, `notification_type`, `channels`
      array, `settings` jsonb for days-before and frequency) and
      `notification_deliveries` for the record. Do not add a parallel mailer path.
- [ ] Reminders stop the moment proof is submitted.
- [ ] Proof accepted **and** rejected both notify; a rejection must say why and
      what happens next, because it restarts the release clock.
- [ ] Every send recorded, so "were they warned?" has an answer.

---

## Environment notes

### Dev hotels

| id | Name | Sell mode | Notes |
| --- | --- | --- | --- |
| 11 | Kinabalu Pine Resorts | `per_room` | 64 rooms, 6 types, 8 rate plans. Seeded by `bin/rails ezee:seed_hotel`. |
| 6 | Grand Pax Resort | **`per_person`** | The only per-pax hotel — use it to demo per-pax pricing. |

### Useful tasks

```bash
bin/rails ezee:seed_hotel              # creates/refreshes hotel 11
bin/rails "ezee:reset_import[11]"      # clears imported bookings AND room inventory
bin/rails business_dates:advance       # moves stale working dates to today (dev only)
```

`ezee:reset_import` clears `room_inventories` deliberately: creating a booking
decrements them and deleting it does not restore them, so without that a second
import starves and looks like a broken importer.

### Known blocker for demoing agent booking

**No agency has a corporate portal login.** The ~150 accounts the eZee import
creates have no contact email, so none can be invited. To demo
`/corporate/bookings` you must first invite a corporate account from the hotel
portal's External Accounts page against an email you control, accept the
invitation, then sign in. A seed task for this was offered but never built.

### Branches from the session that produced this

| Branch | Head | Pushed |
| --- | --- | --- |
| `feat/ezee-reservation-import` | `5c692c056` | yes |
| `feat-vendor-voucher` | `101183516` | yes |
| `feat/grc-tablet-signing` | `231055048` | **local only** |
| `feat/corporate-account-terms` | `efdf24b5d` | **local only** |
| `feat/agent-booking` | `7f97b7417` | **local only** |
| `plan/ta-payments-and-localisation` | `1bf4c2f44` **+ uncommitted work** | **local only** |

`feat/agent-booking` is the base for items 1 and 2 — it contains the corporate
portal booking flow (`CorporatePortal::AgentStaySearch`,
`CreateAgentBooking`, `BookingsController`) that the payment deadline attaches
to. `feat/corporate-account-terms` holds the direct-bill visibility work that
the standard/direct-bill distinction in item 1 depends on.

Four untracked files are unrelated to this work and predate it:
`codebase_consistency_report.md`, `load_test/`, `repomix-output.xml`,
`test_suite_performance_audit.md`. Everything else untracked in the tree **is**
this work — see the migration and new-code lists at the top.

### Still true, and still a blocker for demoing any of item 1

The agent-booking login blocker above applies to the payment deadline too: without
a corporate portal login you cannot see Pay now, the countdown, or submit a slip.
The sweeper can be exercised without one — set `payment_due_at` into the past on
an agent booking and run
`Bookings::ReleaseUnpaidAgentBookings.call` in `bin/rails runner`.
