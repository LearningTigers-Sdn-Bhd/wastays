# Booking Notes — Tech Debt

**Raised:** 24 July 2026
**Context:** Booking Workspace redesign, Phase 2 (Overview sections)
**Status:** Decision pending — no code changes made
**Scope note:** This is a data-model decision. It does not block the Overview layout or Phase 3.

## Summary

There are **four** unrelated mechanisms in this codebase that staff and guests all
colloquially call "notes" or "requests". Two of them overlap enough to be a genuine
duplication; the other two only look similar.

The duplication is real, but the obvious fix (merge everything into one table) is not
achievable, for reasons recorded below.

## The four mechanisms

| | Storage | Author | Lifecycle | Guest-visible |
|---|---|---|---|---|
| `bookings.special_requests` | `text` column | **guest**, at quote/booking time | none — overwritten | **yes** — public pages + voucher PDF |
| `bookings.internal_notes` | `text` column | staff, via Registration Card | none — overwritten | no |
| `booking_notes` | table, one row per note | staff, via workspace | none, but audited | no |
| `housekeeping_requests` / `complaint_requests` | two tables | guest / staff / channel sync | **`pending → in_progress → completed`**, archivable, assignable | partly |

`group_bookings.notes` is a fifth column. **Nothing writes it and nothing reads it.**
Treat it as unwired; do not surface it in any UI.

There is also an `internal_notes` **jsonb** column on `housekeeping_requests` and
`complaint_requests`. Unrelated to the above — it is per-request commentary.

## Confirmed defect: two invisible-to-each-other staff note systems

`bookings.internal_notes` and the `booking_notes` table are both "staff notes on a booking",
written from different screens, and **neither surface shows the other's content**.

- A note typed on the **Guest Registration Card** goes to `bookings.internal_notes`.
- A note typed in the **workspace Overview** goes to `booking_notes`.
- The workspace Overview renders only `booking_notes`. `bookings.internal_notes` is
  invisible there entirely.

This is the part that is unambiguously worth fixing.

## Capability comparison

| Capability | `booking_notes` | `bookings.internal_notes` |
|---|---|---|
| Multiple notes | yes | no — one string |
| Author attribution | yes (`user_id`, `null: false`) | no |
| Per-note timestamp | yes | no |
| Edit history | yes (`edit_history` jsonb + History UI) | no — overwritten |
| Audit-trail entries | yes — `note_added` / edited / deleted | no |
| "N notes" badge on arrivals list | yes | no |

`booking_notes` is strictly the richer system.

## Options considered

### A — Retire `bookings.internal_notes` into `booking_notes` (recommended)

**Blast radius: ~7 app files + one backfill.**

- `app/controllers/hotel_portal/bookings_controller.rb` (param list)
- `app/controllers/hotel_portal/bookings/actions/booking_creation_base_controller.rb` (param list)
- `app/controllers/hotel_portal/bookings/guest_registration_cards_controller.rb` (param list)
- `app/services/bookings/update_guest_registration_card.rb`
- `app/views/hotel_portal/bookings/guest_registration_cards/show.html.erb`
- `app/views/hotel_portal/bookings/actions/booking_creations/_form.html.erb`
- `app/javascript/controllers/registration_card_controller.js`

Backfill existing `bookings.internal_notes` values into `booking_notes` rows, repoint the
Registration Card at the same table, drop the column.

**Loses nothing.** Gains authorship, timestamps, edit history, and audit entries for notes
that currently have none.

### B — Also fold `special_requests` into `booking_notes`

**Blast radius: ~40 app files + 8 spec files. Not achievable in full.**

Requires schema changes to `booking_notes`:

| Change | Consequence |
|---|---|
| add `note_kind` (`internal` / `guest_request`) | acceptable |
| `user_id` → nullable | guests are `Guest`, **not `User`**; weakens `null: false` for all existing staff notes |
| add a guest-visibility rule | table is currently uniformly staff-internal; public pages would need `where(note_kind: "guest_request")`. One wrong scope leaks staff notes to guests. |

**Hard blocker:** `booking_quotes.special_requests` exists — the guest types it **before any
booking exists** — and `booking_notes.booking_id` is `null: false`. The quote-stage column
cannot move. `Api::V1::QuotesController`, `BookingEngine::CreateQuote`, and
`public/quotes/show` keep using it, so the text ends up in **two** places: a column at quote
stage, rows after conversion. That is more duplication than exists today.

Semantic changes that would also need deciding:

| | Today | After |
|---|---|---|
| Editing | overwrite one string | append-only rows with history |
| Voucher PDF | prints *the* special requests | must choose: latest note? concatenate all? |
| Group booking | `ConfirmGroupBooking` writes one string to every child | N duplicate note rows per group |
| Registration Card "Remark" | a textarea | a note list, or a textarea that silently creates notes |

The voucher row is a change to a document handed to guests.

### C — Retire `booking_notes` into the columns

**Blast radius: ~25 files. This is a downgrade, not a consolidation.**

Files affected beyond the workspace:

- `app/queries/hotel_portal/front_desk/arrivals_query.rb`
- `app/presenters/hotel_portal/arrival_presenter.rb` — `notes_count`, `notes?` (arrivals badge)
- `app/services/hotel_portal/reports/arrivals_departures_report.rb:171` — exports latest note body
- `app/services/hotel_portal/reports/outstanding_balance_report.rb:88` — exports latest note body
- `app/services/bookings/create_booking_note.rb` / `update_booking_note.rb` / `delete_booking_note.rb`
  — all three write `Bookings::RecordAuditLog`; deleting them removes three sources of
  `booking_audit_log` entries the Audit Trail destination reads
- `app/controllers/hotel_portal/bookings/actions/internal_notes_controller.rb` + 2 routes
- `app/helpers/hotel_portal/bookings/booking_notes_helper.rb`
- `db/demo_seeds.rb`, `lib/tasks/data_factory.rake`, 5 spec files

Loses every capability in the comparison table above, in a domain where "who wrote this
about the guest, and when" is exactly what is needed when something goes wrong.

## Why `special_requests` resists merging

Four properties, none of which go away:

1. **Guest-authored** — `Guest` is a plain `ApplicationRecord`, not a `User`.
   `booking_notes.user_id` is `null: false`.
2. **Pre-booking** — lives on `booking_quotes` before a `booking_id` exists.
3. **Guest-visible** — rendered on `public/bookings/show` and `public/quotes/show`.
4. **Printed** — `VoucherPdfService` puts it on the guest voucher.

It is a guest-facing field that happens to contain prose. `booking_notes` is a staff-internal
audit-bearing record. They are different in kind, not just in label.

## Related workflow gap (separate from the above)

`special_requests` is a **dead-end field**. A guest writes "need a baby cot"; it lands in a
text column that only the voucher PDF reads. It has no status, so nobody can mark it done,
and it never reaches the housekeeping board — while `HousekeepingRequest`, one tab away, is
built for exactly that and does reach the board.

Two ways to close it:

- **Display-only:** a `Create request` action on Overview that converts guest text into a
  `HousekeepingRequest` on the correct child booking.
- **Structural:** booking confirmation auto-creates a `HousekeepingRequest` from
  `special_requests`, and Overview links to Requests.

## On the "1:1 internal and request notes per booking" requirement

`booking_notes` has **no type column** — the whole table is
`booking_id · body · user_id · created_at · updated_at · edit_history`. Supporting two note
kinds requires a migration; it cannot be done in the view layer.

If a "request" note needs to be actioned — assigned, marked done, seen by housekeeping — it
is **not a note**; it is a `HousekeepingRequest`. A `note_kind` column is only correct if
these are categorised commentary with no lifecycle. That question decides whether this is a
one-column migration or a workflow change.

Naming note: if a note kind is added, do not label it "Requests" — that name is taken by the
housekeeping/complaint destination. `guest_request` / "Guest requests" avoids the collision.

## Recommendation

1. Do **A** as its own change. It is the only pure consolidation, and it loses nothing.
2. Leave `special_requests` where it is.
3. Treat the housekeeping conversion as a separate feature, not part of the notes cleanup.
4. Do not surface `group_bookings.notes` anywhere until something writes it.

## Data caveat

The development database has **zero** rows for all of these: no `special_requests`, no
`bookings.internal_notes`, no `booking_notes`, no `group_bookings.notes`. Every conclusion
above is derived from schema and code paths, **not** from usage evidence.

Before committing to A or C, run a production count of `bookings.internal_notes` (non-blank)
versus `booking_notes`. If staff rely heavily on the Registration Card field and barely use
the workspace one, the backfill direction is still A, but the UI emphasis may need to change.
