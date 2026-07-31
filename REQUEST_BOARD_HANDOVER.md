# Requests board — handover

Branch: `refactor/frontdesk`. Ten commits, `a0de0b9a`..`HEAD`.
Scope: the hotel portal Requests board (`/hotel/:id/requests`) and its archive.

This is where the work got to, what is deliberately unfinished, and the traps
worth knowing before touching it again.

---

## 1. What the feature is

Four kanban columns over **three unrelated tables**, joined at runtime by a
`kind` string:

| kind | table | notes |
|---|---|---|
| `housekeeping` | `housekeeping_requests` | may carry its own `hotel_id`, or reach the hotel only through its booking |
| `complaint` | `complaint_requests` | booking only |
| `checkout` | `check_out_requests` | booking only; no `internal_notes`, no `archived_at` column |

Columns: **Housekeeping**, **Complaints**, **Recently Completed**, **Checkout
Requests**. Plus an **archive** page.

Housekeeping and complaint requests are mostly raised by guests on the
**concierge page** (`Concierge::SubmitGuestRequest`) — not the AI concierge.

### Files

```
app/controllers/hotel_portal/requests_controller.rb          index, column, mutations
app/controllers/hotel_portal/requests/actions/details_controller.rb   detail sheet
app/controllers/concerns/request_action_completion.rb         sheet completion contract
app/models/hotel_portal/requests/date_window.rb              the date range
app/models/hotel_portal/requests/cursor.rb                    where a column got to
app/services/hotel_portal/requests_board.rb                   the board
app/services/hotel_portal/requests_archive.rb                 the archive
app/services/hotel_portal/requests/narrowing.rb               search + status, in SQL
app/services/hotel_portal/requests/status_groups.rb           what a status group means
app/services/hotel_portal/requests/finder.rb                  the one hotel-scoped lookup
app/services/hotel_portal/requests/room_status_sync.rb        what a status change means for rooms
app/services/hotel_portal/requests/completion_webhook.rb      telling the outside world
app/services/hotel_portal/requests/{status,archive,cancel}_updater.rb
app/presenters/hotel_portal/requests_board_presenter.rb
app/presenters/hotel_portal/requests_archive_presenter.rb
app/presenters/hotel_portal/requests/detail_presenter.rb
app/helpers/hotel_portal/requests_helper.rb                   link building
app/views/hotel_portal/requests/                              index, archive, _card,
                                                              _column_page, _date_window,
                                                              column, actions/details/
```

---

## 2. Traps — read before changing anything

**Scope a housekeeping request through `HousekeepingRequest.in_hotel`, never
`where(hotel_id:)`.** A request a dispatcher raised carries its own `hotel_id`;
one a guest raised on the concierge page carries only `booking_id`. Using
`hotel_id` alone makes every guest-submitted request vanish. This is the single
easiest way to break the board.

**`Requests::Finder` is the only way to look up a request by kind + id.** It
holds the tenancy check. There were three copies of it once and the whole point
of the first commit was that there is now one. Do not inline a fourth.

**The cursor's `sort_source` is not the card's `kind`.** A checkout's room
cleaning is a `housekeeping_requests` row displayed as a checkout. The cursor
orders by `(sort_at, sort_source, id)` and ids only distinguish rows inside their
own table — conflate source and kind and page boundaries silently lose cards.
`spec/models/hotel_portal/requests/cursor_spec.rb` has a test that the SQL
predicate and the Ruby sort agree; keep it passing.

**Turbo replaces a frame's *children* and leaves its *attributes* alone.** The
lazy placeholder in `_column_page.html.erb` therefore carries the layout classes
(`flex flex-col gap-3`), not just the response wrapper. Put them only on the
wrapper and the next page's cards arrive unspaced.

**Grid items need `min-w-0`.** A grid item sizes to its content by default, so
one long card title widens the whole board past the viewport and the page scrolls
sideways. `index.html.erb` sets it on the `section` and the header text.

**The date window anchors on the wall clock, not the business date.** It looks
*backward*, so anchoring on a business date waiting on a night audit would end
the window before the requests arriving now. Stay View can anchor on the business
date because it looks forward.

**The window compares timestamps in the hotel's zone.** `requested_at` and
`completed_at` are `datetime`; comparing against a bare `Date` compares against
midnight UTC and moves the boundary for every non-UTC hotel.

**A completed checkout must have `completed_at`.** Otherwise it cannot be placed
in the window and does not appear at all. `StatusUpdater` is the only thing that
completes one (handing over only writes `assigned`/`new`); the factory sets it too.

---

## 3. How it works now

### Reading

Each column is a set of **sources**, each one ordered relation:

| column | sources |
|---|---|
| housekeeping | housekeeping, open statuses, not a cleaning |
| complaint | complaint, open statuses |
| checkout | open checkouts + cleanings no checkout already stands for |
| completed | housekeeping + complaint + checkout, all finished |

Every source is bounded by **hotel + status + the date window**, ordered, and
asked for `limit + 1` rows — one more than the page needs, which is how a column
knows there is another page without counting the rest of it. Results are merged
in the cursor's order and sliced.

Nothing walks `hotel.bookings`. Measured before/after on the same seeded data:

| history | before | after |
|---|---|---|
| 0 bookings | 10 queries, 6 rows | 8 queries, 4 rows |
| 25 bookings | 60 queries, 131 rows | 8 queries, 4 rows |
| 100 bookings | 210 queries, 506 rows | 8 queries, 4 rows |

A spec asserts a hotel with 20 bookings of history asks no more questions than
one without, so it stays flat.

### Which timestamp each column reads

| column | column read |
|---|---|
| housekeeping / complaint / checkout | `requested_at` |
| completed | `completed_at` |
| archive | `archived_at` (checkouts: `updated_at`, they have no such column) |

Outstanding work is placed by when it was asked for, finished work by when it was
finished — otherwise closing something old drops it out of the completed column
on the day it was closed.

### The date range

`Requests::DateWindow`, modelled on `StayView::DateWindow` but **backward**: the
date picked is the newest day shown, the range (7/14/21/30, default 7) is how far
back to reach. Toolbar in `_date_window.html.erb`, submitting through the
existing `auto-submit` controller. No new JavaScript.

It bounds **all four columns**, which is a deliberate product decision — so each
open column shows *"N older requests outside this range"* linking to the widest
range, and narrowing is never silent.

### Lazy loading

`turbo_frame_tag ..., loading: :lazy` — Turbo loads it when scrolled into view.
No IntersectionObserver, nothing added to the importmap. The frame's id is keyed
on the cursor it was asked for, so the page that arrives replaces the placeholder
that asked for it. Route: `GET /hotel/:id/requests/columns/:column?cursor=…`.

Not offset pagination: staff finish things while somebody scrolls, and `OFFSET`
counts rows that have since moved.

### Writing

`StatusUpdater` translates what was asked for into what the record answers to
(a complaint is *resolved* where housekeeping is *completed*; a checkout has a
workflow vocabulary of its own), writes it, and then hands off:

- `Requests::RoomStatusSync` — what the change means for the rooms the request
  covers. Dispatching or starting work makes a room dirty; finishing makes it
  ready, but only once nothing else is outstanding on that room. A complaint
  covers no rooms and it returns early. Per-kind differences live in a `RULES`
  table, the way `HousekeepingTasks::TaskAssignment` holds its own.
- `Requests::CompletionWebhook` — only the finishing transition is announced,
  and each kind spells finished differently.

### The detail sheet

One sheet in the same family as the booking action sheet — empty
`requests_action_sheet` frame in the shell, `request-actions` route scope,
`DetailsController#show`, read-only like `Bookings::Actions::AuditTrailsController`.
`Requests::DetailPresenter` normalises the three kinds so one view serves both
pages.

It replaced **one `<dialog>` per card** (up to ~100 modal subtrees per page load)
that described the same request in different words on each page — and that never
opened on the board at all, because the target sat outside its controller element.

---

## 4. Deliberately unfinished

**The archive still paginates (`Kaminari.paginate_array`).** Infinite scroll there
needs a `<turbo-frame>` between `<tbody>` and `<tr>`, which browsers hoist out of
the table. The fix is converting that table to a div/grid list — which would also
retire its raw-Tailwind 7-column layout and its two remaining native selects'
siblings. **This is the next piece of work.**

**Open work older than 30 days is unreachable** from this page. The counter says
it exists, but the widest range cannot reach it and open work is never archived.
Options: an "all open" range that ignores the window, or letting the counter jump
to a window that covers it.

**Releasing a checkout does not note it in the assignment history**, where
releasing housekeeping does. `StatusUpdater#write_checkout` passes
`record_history: false` to preserve that exactly; `HousekeepingTasks::TaskAssignment`
*does* write history for both kinds, so the odd one out is probably this. Left
as it was rather than levelled up inside a refactor — worth settling on purpose.

**DESIGN.md**: the board still uses raw palette utilities throughout
(`bg-blue-50`, `text-amber-700`, `bg-slate-100` — which does not dark-mode), and
`RequestsArchive` still emits Tailwind class strings **from a service**
(`status_class_for`, `kind_class_for`). The latter is a layering violation, not
cosmetics.

**Drag and drop**: success does a full `window.location.reload()`; failure
silently snaps the card back with no message; there is no keyboard path. Dragging
writes status `"pending"` while the Dispatch button writes `"new"` — the *filter*
that hid the difference is fixed, but both words still get written. Column order
in `localStorage` also resets whenever the filter re-renders the Turbo frame.

**Card actions are still on the cards**, not in the sheet.
`RequestActionCompletion` is wired and unused; it needs `requests#update_status`
to emit `complete_sheet` instead of redirecting.

**`card_action` in the board presenter has a dead branch** — the
`kind == "housekeeping" && status == "pending"` arm is followed by
`status == "pending"`, both calling `dispatch_action`. Trivial.

**Cards are still hashes**, not value objects. `DetailPresenter` is the seed of
the value object the board should eventually build; the board still assembles
~15-key hashes. `RequestsBoard` also still `include`s `url_helpers` and builds
URLs, which is a view concern in a service.

---

## 5. Not a code problem

**The pipeline is split across two unrelated feature flags.** The concierge page
is gated by `ai_concierge_page` (`Public::Concierge::BaseController`); the board
by `task_assignment_minibar_log` (`RequestsController`). A hotel with the first
enabled and the second not is **accepting guest requests into an inbox nobody can
open** — guests get a success page and staff never see the request. Needs a look
at live plan config, not a patch.

**The index migrations are not `CONCURRENTLY`.** No migration in this repo is, so
they follow convention — but `housekeeping_requests` and `check_out_requests` may
be large enough in production for the table lock to matter. Worth checking row
counts before deploying `20260731090100`.

---

## 6. Tests

378 examples across the requests specs, from 34 at the start.

```bash
bin/test spec/services/hotel_portal/requests_board_spec.rb \
         spec/services/hotel_portal/requests_archive_spec.rb \
         spec/requests/hotel_portal/requests_pages_spec.rb \
         spec/requests/hotel_portal/requests \
         spec/services/hotel_portal/requests \
         spec/models/hotel_portal \
         spec/presenters/hotel_portal --serial
```

The ones worth not breaking:

- `cursor_spec.rb` — the SQL predicate and the Ruby sort agree; plus a walk of a
  column where **three tables share one timestamp**, which is where a naive
  cursor loses a row
- `requests_board_spec.rb` — a busy hotel asks no more questions than a quiet one
- `date_window_spec.rb` — the non-UTC boundary, and a lagging business date
- `requests_pages_spec.rb` — every card has one launcher and **no dialog of its
  own** (`css("article dialog")` must stay empty); the lazy placeholder carries
  its layout classes
- `finder_spec.rb` — cross-tenant refusal for all three kinds, including the
  `hotel_id`-nil concierge case

### Known unrelated failure

`spec/requests/hotel_portal/front_desk_spec.rb:808` fails on this branch **and on
a clean `main` checkout** — verified by stashing. Not caused by this work. Also
note `bin/test all` flakes on a different one or two system specs each run;
verify with targeted runs.

---

## 7. Before continuing

Load the board in a browser at all four columns with the range at 30 days. Much
of the layout was changed without a browser available, and two defects were found
that way — the sideways page scroll and the missing gap between lazy-loaded pages.
Both are fixed, but a look is cheaper than the next one.
