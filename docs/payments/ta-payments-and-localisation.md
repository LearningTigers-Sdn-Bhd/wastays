# Travel agent payments, attribution, and a Chinese version

**Status (21 Sep 2026): mostly built.** Sections 1, 2, 4 and 5 shipped on
`plan/ta-payments-and-localisation`; **section 3 (Chinese) is the only strand
not started.** Boxes below are ticked against the code, not the intent. See
[feature-and-bugfix-checklist.md](feature-and-bugfix-checklist.md) for what was
found while building each one, and for the traps.

Four strands, in the order they were raised: a payment deadline that releases
rooms, marking a booking as an agent's, a Chinese translation of the product,
and a checklist of smaller fixes. They are independent and can ship separately.

Terms: **TA** is a travel agent — a `HotelCorporateAccount` of type
`travel_agent`. The portal they sign into is the corporate portal
(`/corporate`).

---

## 1. A payment deadline that releases rooms

An agent books through the corporate portal and must pay within a window the
admin sets. If they do not, the rooms go back on sale.

### Settled

- **Only standard (non-direct-bill) accounts.** A direct-bill agent is invoiced
  on AR terms and settles by agreement; a release clock would contradict the
  credit relationship they were given. `relationship_type` already separates
  the two, and the sheet that edits it now hides billing terms on standard
  accounts, so the two concepts stay visually distinct as well.
- **The clock stops when payment proof is uploaded**, not when it is approved.
  It resumes only if an admin rejects the proof. Releasing rooms an agent has
  actually paid for, because nobody reviewed the slip in time, is the failure
  that would cost the most trust.

### Do not build this on `payment_terms_days`

`hotel_corporate_accounts.payment_terms_days` is AR invoice terms: when an
invoice falls due. A booking hold is a different clock with a different
consequence — one produces an overdue invoice, the other puts rooms back on
sale. Sharing the column would mean changing invoice terms silently changes how
long rooms are held.

The deadline needs its own attribute on the relationship, and its own default on
the hotel for accounts that do not set one.

### There is already an abandoned hold concept

`hotels.group_booking_request_hold_hours` exists as a column, defaulting to 48,
and **no branch references it in application code**. A hold-with-expiry was
started and left. Before adding a third idea in this area, decide whether that
column is the one to revive, rename, or drop — two half-built hold mechanisms
would be worse than either alone.

**[ ] Still open.** This branch added its own `agent_payment_hold_hours` rather
than reviving that column, which is in the local database (from another
branch's migration) but not in this branch's `db/schema.rb`. Reconcile the two
when that branch merges — one of them should go.

### The status question, which decides the whole design

`Booking::STATUSES` includes `pending`, and it is tempting to hold unpaid agent
bookings there. **It would not hold the rooms.** Availability counts only
`confirmed`, `no_show_detected`, `checked_in`, `due_out_detected` and
`checkout_required` — both in `Bookings::AvailableRoomNumbers` and in
`CorporatePortal::AgentStaySearch`. A `pending` booking blocks nothing, so the
room would be sold twice.

So the booking is created **`confirmed`**, exactly as it is today, and carries a
deadline. A sweeper cancels it when the deadline passes. The room is genuinely
held for the whole window, which is the point of the feature, and no
availability rule has to change.

Cancelling releases inventory through the path that already exists for a
cancelled booking. Nothing new is needed to free the room — only to decide when.

### What has to be built

- [x] A deadline on the relationship (and a hotel-level default),
  admin-editable. `hotels.agent_payment_hold_hours` (default 48) with a
  nullable override on `hotel_corporate_accounts`, entered as hours or days.
- [x] `payment_due_at` on the booking, stamped at creation from that setting.
  `Bookings::PaymentHold` is the one place that decides a deadline.
- [x] A state for "proof submitted, clock stopped" that the sweeper honours.
  `ar_payment_submissions` gained an optional `booking_id` so a standard agent
  with no invoice has something to pay against; the sweeper skips any booking
  with a submission awaiting review.
- [x] A recurring sweeper that cancels expired, unpaid, unprotected bookings.
  `Bookings::ReleaseUnpaidAgentBookings` + its job, every 5 minutes in
  `config/recurring.yml`, cancelling through `Bookings::TransitionStatus` so
  the release is audited like any desk cancellation.
- [x] **Pay now** in the TA portal: the amount, the deadline, and a countdown,
  on both the booking list and the booking itself — plus a dashboard panel and
  agent-initiated cancellation while unpaid, which were not in this plan.

**Resolved:** `bin/rails agent_payment_hold:backfill_payment_due_at` stamps a
fresh deadline (anchored to when it runs, not to each booking's original
creation time, so nothing is cancelled the instant it runs with no warning
ever sent) onto every pre-existing confirmed, unpaid, standard-agency booking
that has none. Idempotent; run it once before turning the sweeper on for a
property with existing agent bookings.

### Risks worth naming before building

- [x] **This is an automated, destructive, money-adjacent action.** Every guard
  (proof pending, already paid, already cancelled, hotel disabled the policy)
  has to be checked in the sweeper, not only in the UI.
- [x] **Clock skew against the business date.** The rest of the product reasons in
  the hotel's business date, which does not move until the night audit runs and
  can sit days behind the calendar. A payment deadline is a wall-clock promise
  to an agent. These must not be conflated: use wall-clock time, and say so in
  the code, or a property that skips audits will hold rooms indefinitely.
- [x] **Timezone.** "3 days from now" is in the hotel's timezone, and the agent may
  be in another. The displayed deadline should state which.
- [x] **What if the stay starts inside the window?** A booking made for tomorrow
  with a three-day deadline cannot wait three days. The deadline needs a floor
  at arrival, and the UI has to explain it.
- [x] **An approved slip only settled the AR ledger, not the booking.**
  `ArPaymentSubmission#approve!` cleared `payment_due_at` but never posted
  anything to the booking's own folio, so the desk still saw the stay as fully
  unpaid at checkout despite the hotel having told the agent it was settled.
  `ArPaymentSubmissions::Approve` now posts the payment to `booking.booking_folio`
  (`Folios::Transactions::InsertTransaction`, `system_posting: true`) and syncs
  `payment_status` through `Deposits::SyncBookingPaymentStatus`, inside the same
  transaction as the approval — a folio that cannot take the posting fails the
  approval rather than leaving it half-recorded.
- [x] **A released multi-room booking left its group reading "active."** Each
  room of an agent's group booking has its own deadline, so the sweeper could
  release every one of them and never touch `GroupBooking#status`.
  `Bookings::ReleaseUnpaidAgentBookings` now closes the group once none of its
  rooms are still held.

---

## 2. Marking a booking as the agent's

A reservation created by a TA should say so in the hotel portal: that it came
from an agent, which agent, which person there, and when.

The attribution is half-built already. `CreateAgentBooking` sets
`hotel_corporate_account_id`, so the booking already knows the agency. Two gaps:

- [x] **`source` is `"internal"`**, which is what a staff-keyed booking uses. In any
  report grouping by source, agent bookings are invisible. `BookingSource` has
  no agent key; adding one is a registry change and affects every hotel's source
  list, so it is a decision rather than a detail.
- [x] **The acting person is not recorded.** `CreateManualBooking` receives the
  corporate user and writes audit logs, but nothing on the booking names who at
  the agency made it. Worth capturing at creation; painful to backfill.

Both were cheap, and both are done. `travel_agent` is now a seeded `manual`
`BookingSource` that `CreateAgentBooking` writes (client's decision; existing
agent bookings keep `internal`, no backfill), and `bookings.corporate_booked_by_id`
/ `corporate_booked_at` record who acted.

- [x] The UI half — a badge on the reservation and the workspace, showing
  agency, person and time, from one shared partial fed by
  `HotelPortal::Bookings::AgentAttribution`. It also answers "has the agent
  paid?" from the same presenter the agent's own portal reads.

---

## 3. A Chinese version

### The finding that reshapes this

**The application has no i18n layer.** There are **37 `t()` calls across 867 ERB
templates**; `config/locales` holds a single 31-line `en.yml`. Effectively every
string is hardcoded English.

So this is not "add a translation provider". It is "introduce i18n to a mature
product", and the provider is the small part.

**Not started.** Still 37 `t()` calls across 867 templates and a single 31-line
`en.yml`; there is no translation store, no provider adapter and no locale
switch. Everything in this section is outstanding.

### Scope, settled

TA portal first; guest-facing soon after; hotel portal and admin eventually. So
the design must scale to the whole product even though the first slice is small.

Templates by surface, which is the real sizing:

| Surface | Templates |
| --- | --- |
| Corporate (TA) portal | **29** |
| Guest portal | 7 |
| Public (booking, concierge, registration card) | 49 |
| Admin | 76 |
| Hotel portal | **553** |
| Shared components | 54 |

The TA portal is 29 templates — a genuinely tractable first slice, and a fair
test of the approach before committing to 553.

### The approach, and the one path to rule out

Two ways to translate an app with hardcoded strings:

1. **Extract strings into i18n keys, then translate the keys.** Correct, and the
   large mechanical job. Machine translation fills the keys; a human corrects
   them; the corrections live in the database and win.
2. **Translate rendered HTML at response time.** Avoids extraction entirely.

**Rule out (2).** It cannot distinguish chrome from data, so it would translate
guest names, hotel names, addresses, agency names and free-text notes along with
the labels. In a system holding money and legal documents that is not a cosmetic
risk. It is also slow, breaks markup, and makes caching per-page almost
meaningless because every page contains unique data.

So: extraction, surface by surface, starting with the 29.

### The firewall premise needs correcting

The concern was picking a provider not blocked by the Great Firewall. If
translation happens **server-side and is cached in the database**, the provider
is called from our server, not the guest's browser, and the firewall is
irrelevant to that choice. It matters only for a client-side widget — the Google
Translate drop-in being the usual example — which we are not using.

What *does* need China attention is our own delivery: fonts, CDN assets and
third-party scripts a Chinese visitor's browser must fetch. That is a separate
piece of work from translation, and worth checking before claiming the site
works in China.

With the firewall out of the way, pick on quality, cost and correctability:

- **DeepL** — strongest Chinese output, paid, simple API.
- **Self-hosted LibreTranslate** — free, no data leaves our infrastructure,
  weaker output, and we own the uptime.
- **Azure Translator** — solid, and has a China region if data residency is ever
  required.

Recommendation: whichever is chosen, put it behind an adapter. The provider will
change; the cached translations and the corrections must survive that.

### The design as proposed holds up

Translate once, cache in the database, fall back to the source string, allow
manual correction, allow marking a string "never translate". That is the right
shape. Specifics worth fixing now:

- [ ] **Corrections outrank machine output permanently.** A re-translation must
  never overwrite a human-corrected string.
- [ ] **Financial, legal and tax strings should be human-translated from the
  start** — e-invoice terminology, "non-refundable", "credit limit", tourism
  tax. A wrong machine rendering of those is a commercial or compliance problem,
  not a typo. Machine translation is for the long tail.
- [ ] **Never translate data.** Only keys. Guest names, hotel names, agency names,
  amounts and free text pass through untouched.
- [ ] **Translate per page, on demand**, as proposed — the first request for a
  locale populates what that page needs, rather than the whole catalogue.
- [ ] **A superadmin screen** to review, correct, search and lock strings.

### Open

- Traditional or Simplified Chinese? They are not interchangeable, and the
  answer follows the market: Simplified for mainland, Traditional for Taiwan and
  Hong Kong. Supporting both doubles the review effort, not the machine cost.
- Do dates, currency and number formats change with the locale, or only words?
- Does a TA choose a language on their account, or per session?

---

## 4. The checklist

### [x] i. StayView booking takes 00:00 instead of the hotel's hours

Real. `Bookings::ScheduledStay.at_hotel_time` applies the property policy time
**only when handed a date-only value**; anything matching `\d[T ]\d` is parsed
literally. So a form sending `2026-09-20 00:00` gets midnight, correctly, from a
service doing what it was told.

The fix is at the boundary — send a date and let the service apply the policy —
not in the service. Worth checking the other creation paths for the same shape
while in there.

**Built.** The real cause was `hotel.bookings.build` assigning attributes before
the association set the owner, so `at_hotel_time` never ran. `Booking` now
re-applies the policy in a `before_validation` (covering every creation path)
and the Sheet controller assigns the hotel first.

### [x] ii. Payment proof does not display for the hotel admin

**Needs reproducing before it is scoped.** In
`hotel_portal/ar_payment_submissions/show`, the slip link renders
*unconditionally*: `rails_blob_path(@submission.slip, …)` with no `attached?`
guard. An unattached slip would raise rather than render nothing, which does not
match "doesn't display". So either the screen in question is a different one, or
the attachment is not arriving.

Reproduce first: upload a proof as a TA, then open it as hotel admin, and
establish whether the blob exists. Fixing the guard is a minute's work and may
fix nothing.

**Built.** Slips attached fine; the gap was reachability — the approve/reject
screen showed no slip at all, and `ArPayment` had no inverse association. A
shared `_slip` partial now appears on all three screens, and the unguarded
`rails_blob_path` says "No slip on file" instead of raising.

### [x] iii. Remove card payment for TAs, bank transfer only

Small. `corporate_portal/ar_payments/choose_method` offers a Razorpay card path
alongside the submission route. Removing the option is straightforward; decide
whether the gateway path is removed for TAs only or disabled outright, and
whether any in-flight card payments need handling.

**Built.** TAs only, via `HotelCorporateAccount#gateway_payments_allowed?`;
other corporate types keep the gateway. Zero in-flight intents, so nothing had
to be drained. Enforced in the view *and* in `CorporateArPayments::CreateIntent`,
since hiding a tile does not stop a POST.

### [x] iv. Colour-code housekeeping room status

Agreed, and larger than described. `RoomStatus::STATUSES` holds **seven**
values, not three: `ready`, `dirty`, `cleaning`, `awaiting_inspection`,
`inspection_failed`, `out_of_service`, `late_checkout_detected`. Note the clean
state is `ready`.

Seven states cannot be separated by hue alone, and colour alone fails a
colourblind user in any case. Each state needs a colour **and** an icon or
shape, with the pair used consistently in the housekeeping page, StayView and
the room cards — the same status should not look different in two places.

**Built.** `Rooms::StatusPresentation` is now the single colour *and* icon map
(StayView's private, divergent copy is gone), the legend is derived from
`RoomStatus::STATUSES` so a new status cannot ship undocumented, and a spec
asserts that statuses sharing a badge variant have distinct icons.

---

## 5. Payment reminder emails

Reuse what exists: `notification_configs` is per hotel, keyed by
`notification_type`, with a `channels` array and a `settings` jsonb — which is
where the policy lives (days before due, repeat frequency, stop conditions).
`notification_deliveries` already records what was sent. A new mailer path
outside this would duplicate both.

The policy needs its own short spec, but three rules are already clear:

- [x] **Reminders stop the moment payment proof is submitted**, for the same
  reason the release clock does. The scheduler and the sweeper share one
  predicate, `Bookings::PaymentHoldScope`, rather than each keeping a copy.
- [x] **Proof accepted and proof rejected both notify**, and a rejection must
  say why and what happens next. `ArPaymentSubmissions::Approve` / `::Reject`
  fire the mail as a service's side effect, not a model callback.
- [x] **Every send is recorded**, so a dispute about whether an agent was warned
  has an answer — including a `skipped` row when there is nobody to write to.

Built on the existing `notification_configs` / `notification_deliveries` rails
with no migration: `agent_payment_reminder` is a new type whose `settings` holds
`offsets_hours` (default `[24, 4]`), editable on Settings → Notifications, email
only. The scheduler runs hourly and sends the smallest open offset.

---

## 6. Sequencing

The checklist items are independent of everything else and unblock quickly; the
payment hold is the largest and most delicate; the Chinese work is the longest
and most mechanical but carries the least risk of breaking existing behaviour.

A reasonable order:

1. [x] **The checklist** (§4) — four small items, immediate value, no design
   debt. Item ii needs reproducing first.
2. [x] **TA attribution** (§2) — small, and the data half should land before
   more agent bookings exist to backfill.
3. [x] **The payment hold** (§1) with its reminder policy (§5) — the substantial
   feature, and the one that needs the most care in review.
4. [ ] **Chinese** (§3) — the TA portal's 29 templates as a first slice, proving
   the architecture before the 553.

Nothing here forces that order; the strands are independent.
