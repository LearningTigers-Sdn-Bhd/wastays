# Checklist: TA payments, attribution, Chinese, and four fixes

**Nothing here is built.** This is the work queue, written so a fresh session can
pick it up without the conversation that produced it.

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
- [ ] **Restart the server after any Gemfile change.** Bundler locks the bundle
      at boot; a long-lived Puma keeps whatever it started with. A `LoadError`
      for a gem that is plainly in the Gemfile means a stale process, not a bad
      branch.
- [ ] Run the full suite before claiming done. There is a coverage gate
      (`spec/services/service_spec_coverage_spec.rb`) requiring one spec file per
      `app/services` file; new services fail CI without one.

---

## Bugs (item 4) — smallest, do first

### [ ] i. StayView booking uses 00:00 instead of the hotel's hours

`Bookings::ScheduledStay.at_hotel_time` is **correct** and should not be
changed. It applies the property policy time only when handed a *date-only*
value; anything matching `\d[T ]\d` is parsed literally. So a caller is sending
`2026-09-20 00:00` and getting exactly that.

- Find the StayView creation path and send a date, not a datetime.
- Check the other creation paths for the same shape while in there.
- `PropertyPolicy#check_in_time` / `#check_out_time` are the source of truth;
  `ScheduledStay::DEFAULT_CHECK_IN_TIME` (15:00) is only the fallback.

### [ ] ii. Payment proof not visible to hotel admin

**Reproduce before scoping. The reported symptom does not match the code.**

In `app/views/hotel_portal/ar_payment_submissions/show.html.erb` the slip link
renders **unguarded**: `rails_blob_path(@submission.slip, …)` with no
`attached?` check. An unattached slip would *raise*, not render nothing. So
either that is not the screen in question ("Financials → Payment Record"), or
the attachment never arrives.

- Upload a proof as a TA, open it as hotel admin, and establish whether the blob
  exists before changing anything.
- `ArPaymentSubmission has_one_attached :slip`.
- Add the `attached?` guard regardless — it is a latent 500 — but do not assume
  it is the fix.

### [ ] iii. Remove card payment for TAs, bank transfer only

- `app/views/corporate_portal/ar_payments/choose_method.html.erb` offers a
  Razorpay card path beside the submission route.
- Decide: remove the option for TAs only, or disable the gateway path entirely.
- Check for in-flight card payments before removing the route.

### [ ] iv. Colour-code housekeeping room status

**There are seven statuses, not three**, and the clean one is `ready`:

`ready`, `dirty`, `cleaning`, `awaiting_inspection`, `inspection_failed`,
`out_of_service`, `late_checkout_detected` (`RoomStatus::STATUSES`).

- Seven states cannot be separated by hue alone, and colour alone fails
  colourblind users. Give each a colour **and** an icon or shape.
- Apply the same pair in the housekeeping page, StayView and the room cards —
  one status must not look different in two places.
- `RoomStatus::ASSIGNABLE_STATUSES` is `["ready"]` only; that distinction is
  worth showing.

---

## Feature: TA payment deadline that releases rooms (item 1)

Settled: **standard (non-direct-bill) accounts only**; **the clock stops when
payment proof is uploaded**, not when approved, and resumes only on rejection.

### Traps that decide the design

- [ ] **Do not hold the booking in `pending`.** Availability counts only
      `confirmed`, `no_show_detected`, `checked_in`, `due_out_detected`,
      `checkout_required` — in both `Bookings::AvailableRoomNumbers` and
      `CorporatePortal::AgentStaySearch`. A `pending` booking blocks nothing, so
      **the room would be sold twice.** Create it `confirmed` and carry a
      deadline.
- [ ] **Do not reuse `hotel_corporate_accounts.payment_terms_days.`** That is
      when an AR invoice falls due. Sharing it makes an invoice-terms change
      silently move inventory. Add a separate attribute plus a hotel default.
- [ ] **`hotels.group_booking_request_hold_hours` already exists** (default 48)
      and **no branch uses it in application code**. Revive, rename or drop it —
      do not add a third hold concept beside it.
- [ ] **Use wall-clock time, not the business date.** The business date only
      moves when the night audit runs and can sit days behind; a deadline is a
      promise to an agent. Say so in the code.
- [ ] **Floor the deadline at arrival.** A booking made for tomorrow cannot wait
      three days. The UI has to explain this.
- [ ] State the timezone on screen — the agent may not be in the hotel's.

### To build

- [ ] Deadline setting on the relationship + hotel-level default, admin-editable.
- [ ] `payment_due_at` on the booking, stamped at creation.
- [ ] Sweeper job: cancel expired, unpaid, unprotected bookings. Idempotent, and
      **it must log every release** — an automated cancellation nobody can audit
      is not acceptable in a money path.
- [ ] Sweeper skips any booking with an `ArPaymentSubmission` awaiting review.
- [ ] **Pay now** in the TA portal: amount, deadline, countdown, on the list and
      the booking.

---

## Feature: mark a reservation as the agent's (item 2)

Half done already — `CorporatePortal::CreateAgentBooking` sets
`hotel_corporate_account_id`, so the booking knows the agency.

- [ ] **`source` is `"internal"`**, same as a staff-keyed booking, so agent
      bookings are invisible in any source-grouped report. `BookingSource` has no
      agent key; adding one is a registry change affecting every hotel.
- [ ] **The acting person is not recorded.** Capture which corporate user made
      it — cheap now, painful to backfill.
- [ ] Badge on the reservation and the booking workspace: agency, person, time.

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
| `plan/ta-payments-and-localisation` | `cd62dac2a` | **local only** |

`feat/agent-booking` is the base for items 1 and 2 — it contains the corporate
portal booking flow (`CorporatePortal::AgentStaySearch`,
`CreateAgentBooking`, `BookingsController`) that the payment deadline attaches
to. `feat/corporate-account-terms` holds the direct-bill visibility work that
the standard/direct-bill distinction in item 1 depends on.

Four untracked files are unrelated to this work and predate it:
`codebase_consistency_report.md`, `load_test/`, `repomix-output.xml`,
`test_suite_performance_audit.md`.
