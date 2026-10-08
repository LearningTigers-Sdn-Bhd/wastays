# Checklist: TA payments, attribution, Chinese, and four fixes

**Status (21 Sep 2026).** The four bugs, the agent attribution (item 2), the TA
payment deadline (item 1) and the reminder/notification work (§5) are built on
`plan/ta-payments-and-localisation`. **Only the Chinese version (item 3) is
outstanding.** Ticked boxes below are done and specced; unticked ones are not.

Item 1 and item 2 were committed in `4674031a5`. On top of that, uncommitted in
the working tree: payment visibility on the corporate dashboard and both booking
lists, agent-initiated cancellation, the reminder and accept/reject/release
notifications, and hours-or-days on the payment hold. **None of that round adds a
migration** — it uses columns that already exist, which also means `db/schema.rb`
should not move at all.

> The dev **and** test databases already have all four of `4674031a5`'s
> migrations applied.

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

### And from the round after it (uncommitted)

- `app/services/bookings/payment_hold_scope.rb` — **the** predicate for "held"
  and "clock stopped". The sweeper and the reminder scheduler both call it;
  neither keeps a copy.
- `app/services/notifications/` — `agent_payment_reminder_scheduler.rb` (+ its
  hourly job), `queue_agent_payment_notice.rb`, `agent_recipient.rb`,
  `publish_agent_payment_staff_notification.rb`,
  `payload_builders/agent_payment_notice.rb`.
- `app/services/ar_payment_submissions/{approve,reject}.rb` — wrap the model
  methods so the notification is a service's side effect, not a callback.
- `app/services/corporate_portal/cancel_agent_booking.rb` +
  `app/controllers/corporate_portal/booking_cancellations_controller.rb`.
- `app/queries/corporate_portal/bookings_awaiting_payment_query.rb` and
  `app/presenters/corporate_portal/dashboard_payments_presenter.rb`.
- `app/presenters/hotel_portal/bookings/agent_attribution.rb` — one hash, now
  read by both hotel-portal presenters that feed the agent badge.
- `app/models/concerns/agent_payment_hold_unit.rb` — hours or days, no column.
- `app/views/notification_mailer/_agent_payment_notice.html.erb` + four thin
  views.

### Verification at handoff

Rubocop clean; Brakeman 0 warnings. System specs were not run. The full run
(`bundle exec rspec --exclude-pattern "spec/system/**/*"`) has one known
pre-existing failure, `panels_ui/table_spec.rb:69`, which fails on clean `HEAD`
too.

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

## Feature: payment visibility, and an agent cancelling — **built**

### Where the money shows now

- **Corporate dashboard** — a "Bookings awaiting payment" panel, separate from
  the outstanding AR tile on purpose: an overdue invoice is chased, but an
  unpaid booking loses the rooms. Count, total per currency, overdue and
  under-review counts, the soonest five, and Pay now.
- **Corporate bookings list and booking page** — a chip per booking, from
  `BookingPaymentPresenter#badge_label` / `#badge_variant`: Paid · Awaiting
  payment · 2 days left · Slip under review · Payment overdue · Cancelled.
- **Hotel portal reservation** — the agent badge's popover now answers "has the
  agent paid?", and the badge itself turns amber when due and red when overdue.
  It reads the **same presenter** the agent's own portal reads, so the desk and
  the agent can never be shown different answers.

`CorporatePortal::BookingsAwaitingPaymentQuery` is the one definition of
"awaiting payment", so the dashboard, the list and the sweeper agree.

### The N+1 the badge would otherwise have caused

The badge asks about `ArPaymentSubmission` for every row. `Booking` now
`has_many :ar_payment_submissions` (nullify, not destroy — a submission is a
record of money that was claimed and outlives the booking), the presenter uses
that association **when the caller preloaded it** and queries otherwise, and the
four front-desk queries preload it. Single-booking callers are unaffected.

### Agent-initiated cancellation

`POST /corporate/bookings/:id/cancellation` — its own resource rather than
`#destroy`, because nothing is deleted. `CorporatePortal::CancelAgentBooking`
goes through `Bookings::TransitionStatus`, which already releases inventory and
writes the `BookingAuditLog`, so **the rooms tally through exactly the path a
desk cancellation takes** and there is no second place for the counts to drift.

- Kept as cancelled history: it stays on the agent's list with a Cancelled chip
  and in the hotel's reservations like any other cancellation.
- **Only while unpaid** — confirmed or pending, before arrival, unpaid, and no
  slip in the review queue. Once money is with the hotel, only the hotel can
  cancel, because only the hotel can decide what happens to it. A refund an
  agent triggers themselves was deliberately not built.
- **The whole group goes.** A multi-room stay is several bookings; releasing
  three of four rooms would leave a reservation nobody meant to keep.
- `payment_due_at` is cleared, so the sweeper never looks at it again.
- The button is rendered from the same object the controller acts through, so
  the agent is never shown a button that answers with a refusal.

### Hours or days on the payment hold

`AgentPaymentHoldUnit` on `Hotel` and `HotelCorporateAccount`. The stored
`agent_payment_hold_hours` stays the one canonical number — `Bookings::PaymentHold`
is unchanged — and the unit is derived on the way out (`72` reads back as
"3 days", `36` as "36 hours"). **No migration**, which matters given the schema
drift trap above.

Amount and unit arrive as two params and `assign_attributes` applies them in hash
order, so neither writer converts anything: a `before_validation` resolves the
pair. Converting in the writer would make the answer depend on which field the
form rendered first.

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

## Feature: payment reminder emails (§5 of the plan) — **built**

All of it on the existing `notification_configs` / `notification_deliveries`
rails, with **no migration**: `notification_deliveries` already belongs to a
booking, and the hold columns already exist.

- [x] Reuse `notification_configs`. `agent_payment_reminder` is a new
      notification type whose `settings` holds `offsets_hours` (default
      `[24, 4]`), configurable on Settings → Notifications. **Email only** — it
      goes to a business contact, and the WhatsApp payload builders are all
      guest-shaped.
- [x] Reminders stop the moment proof is submitted. The scheduler and the
      sweeper call one shared predicate, `Bookings::PaymentHoldScope`, rather
      than each carrying a copy: two copies drifting apart is how an agent gets
      cancelled without warning, or chased about a booking that was never at
      risk.
- [x] Proof accepted **and** rejected both notify. `ArPaymentSubmissions::Approve`
      and `::Reject` wrap the model methods and fire the mail — a service, not a
      model callback, so a submission approved in a console does not send.
      `Reject` reloads the booking first, because `reject!` has already extended
      `payment_due_at` and quoting the old deadline would be worse than none.
- [x] Every send recorded. `Notifications::QueueAgentPaymentNotice` writes a
      delivery even when there is **nobody to write to** (status `skipped`), so
      "were they warned?" has an answer either way.
- [x] The sweeper now notifies. `Bookings::ReleaseUnpaidAgentBookings` queues
      `agent_booking_released` after a successful release; notifying can fail
      without undoing the cancellation.

### One reminder per run, not the whole series

With offsets of 24 and 4 hours, a booking made three hours before its deadline
has passed both windows at once. The scheduler sends the **smallest open offset**
and records the larger ones as `skipped` — so the agent gets one mail, and the
row still says why the other did not go.

The idempotency key carries `payment_due_at`, so a rejection that extends the
deadline starts a **fresh** series against the new date, with the old rows
intact.

`Notifications::AgentPaymentRemindersJob` runs hourly (`config/recurring.yml`).
Hourly rather than by the minute: the offsets are whole hours and nothing is
queued ahead, so a finer schedule would only ask the same question sixty times
as often.

### The hotel's side, on the existing bell

`Notifications::PublishAgentPaymentStaffNotification` raises a `StaffNotification`
for everyone holding `manage_ar_payments`, on two events:

- **a slip arrived** — the agent's clock is stopped while it sits there, so an
  unreviewed queue costs the hotel the sale it is holding;
- **rooms were released** — a reservation disappearing without anyone touching
  it is otherwise a phone call nobody can answer.

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
a corporate portal login you cannot see Pay now, the countdown, the dashboard
panel, or the Cancel booking button.

What **can** be exercised without one, in `bin/rails runner`: set
`payment_due_at` on an agent booking, then

```ruby
Notifications::AgentPaymentReminderScheduler.call   # needs an enabled config
Bookings::ReleaseUnpaidAgentBookings.call
```

and read `NotificationDelivery.where(booking: booking)` plus letter_opener. The
reminder needs a `NotificationConfig` with `notification_type:
"agent_payment_reminder"` and `enabled: true` for that hotel — there is none by
default, on purpose.
