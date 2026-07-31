# Requests board — handover

Branch: `refactor/frontdesk`, `a0de0b9a`..`HEAD`.
Scope: the hotel portal Requests board (`/hotel/:id/requests`), its archive, and
the sheet they share.

This is where the work got to, what is deliberately unfinished, and the traps
worth knowing before touching it again.

**Nothing here has been looked at in a browser.** The layout, the drag gestures,
the autoscroll and the keyboard path are covered by specs asserting rendered
structure and server responses, which is not the same as having seen them work.
Read §7 before continuing.

---

## 1. What the feature is

Five lanes over **three unrelated tables**, joined at runtime by a `kind` string:

| kind | table | notes |
|---|---|---|
| `housekeeping` | `housekeeping_requests` | may carry its own `hotel_id`, or reach the hotel only through its booking |
| `complaint` | `complaint_requests` | booking only |
| `checkout` | `check_out_requests` | booking only; no `internal_notes`, no `archived_at` column |

Lanes, in the order the board opens with: **Housekeeping**, **Complaints**,
**Checkout Requests**, **Recently Completed**, **Archived**. That order is
declared once, by `Requests::Column`; `RequestsBoard::COLUMNS` and the header
count pills both read from it rather than repeating it.

The archive is both a lane and a page. The lane is the recent slice, bounded by
the board's date window. `/hotel/:id/requests/archive` is the full record, with
kind and status filters of its own and no date bound worth speaking of — "show me
every cancelled checkout" is a records question, not a board question.

Housekeeping and complaint requests are mostly raised by guests on the
**concierge page** (`Concierge::SubmitGuestRequest`) — not the AI concierge.

### Files

```
app/controllers/hotel_portal/requests_controller.rb          index, column, move, mutations
app/controllers/hotel_portal/requests/actions/details_controller.rb   detail sheet
app/controllers/concerns/request_action_completion.rb         sheet completion contract
app/models/hotel_portal/requests/column.rb                    what a lane is
app/models/hotel_portal/requests/card.rb                      what a card is
app/models/hotel_portal/requests/cursor.rb                    where a lane got to
app/models/hotel_portal/requests/date_window.rb               the date range
app/services/hotel_portal/requests/paging.rb                  reading sources a page at a time
app/services/hotel_portal/requests_board.rb                   the board
app/services/hotel_portal/requests_archive.rb                 the archive, as sources
app/services/hotel_portal/requests/move.rb                    putting a request in a lane
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
app/javascript/controllers/requests_board_controller.js       the board's gestures
app/views/hotel_portal/requests/                              index, archive, _card,
                                                              _column_page, _date_window,
                                                              column, move.turbo_stream,
                                                              actions/details/
```

---

## 2. Traps — read before changing anything

**A card's `kind` is not the table it is in.** A checkout's room cleaning is a
`housekeeping_requests` row displayed as a checkout. `Card#kind` is the badge and
what a lane will accept; `Card#record_kind` is the table. Anything reaching the
record — a URL, `Finder`, `Move`, the `dom_id` — takes `record_kind`. Building a
URL from the badge sends a housekeeping id to `check_out_requests`, which is
exactly how every action on a cleaning card came to raise `RecordNotFound`.
`card_reachability_spec.rb` pins this per lane; three of its examples fail if
`record_kind` falls back to `kind`.

**Scope a housekeeping request through `HousekeepingRequest.in_hotel`, never
`where(hotel_id:)`.** A request a dispatcher raised carries its own `hotel_id`;
one a guest raised on the concierge page carries only `booking_id`. Using
`hotel_id` alone makes every guest-submitted request vanish.

**`Requests::Finder` is the only way to look up a request by kind + id.** It
holds the tenancy check. There were three copies of it once. Do not inline a
fourth.

**The cursor's `sort_source` is not the card's `kind` either** — same reason as
above, one layer down. The cursor orders by `(sort_at, sort_source, id)` and ids
only distinguish rows inside their own table. `cursor_spec.rb` has a test that
the SQL predicate and the Ruby sort agree; keep it passing.

**A lane's first-page frame is rendered even when the lane is empty.** A moved
card arrives as a `prepend` into that frame, which has to exist to be a target.
The empty-state panel sits beside it, not instead of it.

**Prepending a moved card is correct, not a shortcut.** A lane sorts by the
timestamp the move just set — `completed_at`, `archived_at` — so the moved card
genuinely is the newest thing in its destination. If a lane is ever ordered by
something the move does not touch, this stops being true.

**Turbo replaces a frame's *children* and leaves its *attributes* alone.** The
lazy placeholder in `_column_page.html.erb` therefore carries the layout classes
(`flex flex-col gap-3`), not just the response wrapper.

**Below `xl` the columns must stay unconstrained in height.** Given a height they
scroll inside themselves, and the lazy placeholder then only comes into view on a
scroll a phone user has no reason to make. This has already regressed once.

**The date window anchors on the wall clock, not the business date.** It looks
*backward*, so anchoring on a business date waiting on a night audit would end
the window before the requests arriving now.

**The window compares timestamps in the hotel's zone.** `requested_at` and
`completed_at` are `datetime`; comparing against a bare `Date` compares against
midnight UTC and moves the boundary for every non-UTC hotel.

**A completed checkout must have `completed_at`.** Otherwise it cannot be placed
in the window and does not appear at all.

---

## 3. How it works now

### Reading

Every lane is a set of **sources** — an ordered relation, its sort column, and
something that builds a `Card` from a row. `Requests::Paging` reads them: each
source is asked for `limit + 1` rows, results are merged in the cursor's order
and sliced, and the extra row is how a lane knows there is another page without
counting the rest of it.

| lane | sources |
|---|---|
| housekeeping | housekeeping, open statuses, not a cleaning |
| complaint | complaint, open statuses |
| checkout | open checkouts + cleanings no checkout already stands for |
| completed | housekeeping + complaint + checkout, all finished |
| archived | whatever `RequestsArchive#sources` says — the same three, archived |

`RequestsArchive#sources` is public for exactly that reason: the board reads them
the way it reads its own, so there is one description of what the archive is and
two things reading it.

### Which timestamp each lane reads

| lane | column read |
|---|---|
| housekeeping / complaint / checkout | `requested_at` |
| completed | `completed_at` |
| archived | `archived_at` (checkouts: `updated_at`, they have no such column) |

### Lazy loading

`turbo_frame_tag ..., loading: :lazy` — Turbo loads it when scrolled into view.
No IntersectionObserver, nothing in the importmap. The frame's id is keyed on the
cursor it was asked for, so the page that arrives replaces the placeholder that
asked for it. Route: `GET /hotel/:id/requests/columns/:column?cursor=…`.

Not offset pagination: staff finish things while somebody scrolls, and `OFFSET`
counts rows that have since moved.

### Moving a request

`PATCH /hotel/:id/requests/move` is the only way a card changes lane, and **both
the drag and the buttons go through it**. That is the point: dragging used to
write `"pending"` where the Dispatch button beside it wrote `"new"` for the same
intent.

`Requests::Move` decides whether the move is allowed and what it takes:
`Column#transition_for` says what the destination means for that kind, and a
request leaving the archive is unarchived *before* it is given a status, because
an archived request in an open lane shows in neither. It answers with a `Result`
naming both lanes.

`move.turbo_stream.erb` sends back only what changed: remove the card, prepend it
where it went, update both counts, clear the empty state. Pages somebody has
already scrolled into other lanes stay where they are — which is why this is not
a redirect. A redirect can only refill the one frame it was asked from, and a
move always leaves one lane and joins another.

`Move` takes `kind` **and** `display_kind`. What a lane accepts is answered for
what the operator saw; the record is reached by what it is.

### Drag and drop

Kept, and finished:

- Cards move between lanes; the board **autoscrolls** when a drag nears its edge,
  because most lanes are off-screen once five of them scroll sideways.
- **Keyboard**: Enter or Space picks a card up, arrows walk it between lanes,
  Enter drops it, Escape gives up. Lanes reorder with arrows on the grip handle.
- A refused move **says why** in `#requests_board_flash` instead of snapping the
  card back without a word.
- **All five lanes reorder**, including the two that take no cards — where a lane
  sits is the operator's business. Order persists in `localStorage`, and an order
  saved before a lane existed places what it knows and appends the rest.
- **Checkout accepts no cards.** A checkout request is raised by a guest checking
  out; a drop there would be inventing a record.

### Layout

From `xl`, the board scrolls sideways inside a `PanelsUI::ScrollArea`
(`orientation: :horizontal`) with fixed-width lanes, each scrolling down inside
itself. Below `xl` the lanes stack full width and the page scrolls them; the
scroll area is inert at that size.

### The detail sheet

One sheet in the same family as the booking action sheet — empty
`requests_action_sheet` frame in the shell, `request-actions` route scope,
`DetailsController#show`, read-only. `Requests::DetailPresenter` normalises the
three kinds so one view serves the board and the archive page.

---

## 4. Deliberately unfinished

**The board costs far more than it used to.** Measured on a seeded hotel:
`board_columns` alone is **36 queries** against the 8 it was at four columns, and
a full render — columns, counts, older-open counts — is **~60**. An *empty*
hotel still costs ~44. The guarantee that survived is the one the spec asserts:
a hotel with years of history asks no more than a quiet one, so the slope is
still flat. The constant grew about sixfold, from a fifth lane with three
sources of its own plus a `COUNT` per source per lane. **This is the strongest
argument for the lane toggles below**, which should skip a hidden lane's read
*and* its count — `wanted_kind?` returning `.none` in `RequestsArchive` is the
pattern.

**Lane visibility toggles are not built.** `show_[lane]` as a
`PanelsUI::ToggleGroup(type: :multiple)`, which already dispatches native
`change` and so works with the existing `auto-submit` controller. Two traps
found while scoping: `form_with url:` has no object, so `value:` must be passed
explicitly; and `auto-submit#cleanupEmptyInputs` disables empty-valued inputs on
GET, so an all-off state would vanish entirely and read as a fresh load — it
needs a non-empty sentinel. Whatever key it uses must join
`RequestsHelper::PRESERVED_FILTER_KEYS` or lazy frames will drop it.

**The date range is 7/14/21/30 and bounds every lane.** Narrowing it was raised
and deliberately not done yet: the window bounds the *open* lanes too, so a short
range turns an inbox into a keyhole, and the "N older requests outside this
range" counter can only reach as far as the widest option. The proposal on the
table is to re-scope rather than shrink — let the window govern Completed and
Archived, and leave the open lanes unbounded, since open work is self-limiting.
Then 1/3/5/7 is right for the lanes that grow without end, and no open work
becomes unreachable.

**Open work older than 30 days is unreachable** from the board. The counter says
it exists; the widest range cannot reach it and open work is never archived.
Resolved by the re-scope above, if it happens.

**A checkout has no `archived_at` column**, so `updated_at` stands in for it —
in the archive lane, the archive page, and the ordering of both. Any write to an
archived checkout therefore pulls it back to the top of the archive. A real
column would settle it; it is a migration, not a patch.

**The archive page still turns pages with Newest/Older buttons** while every lane
lazy-loads. Two paging UXes in one feature. The page is a table, and a
`<turbo-frame>` between `<tbody>` and `<tr>` is hoisted out by browsers, so this
needs the table converted to a div list first.

**DESIGN.md**: the board still uses raw palette utilities throughout
(`bg-blue-50`, `text-amber-700`), `font-black`, and decorative uppercase — §2 and
§3. `Column` now holds those class strings, which at least means one place to fix
rather than five, but they are still the wrong tokens.

**`RequestsBoard` and `RequestsArchive` still `include url_helpers`** and build
URLs into cards. That is a view concern in a service. `Card` is the right place
to have stopped, and the URLs should move to the presenter.

**`RequestActionCompletion` is wired but unused.** `DetailsController` includes
it; nothing calls `complete_request_action`. Card actions still live on the
cards rather than in the sheet.

---

## 5. Not a code problem

**Cleaning cards are broken in production right now.** Every action on a
checkout's room cleaning — Done, Archive, the detail sheet — has been raising
`RecordNotFound` because the URL was built from the badge rather than the table.
The fix is on this branch and unshipped. Worth counting how many such rows exist
on live boards before deciding how to sequence the deploy.

**The pipeline is split across two unrelated feature flags.** The concierge page
is gated by `ai_concierge_page` (`Public::Concierge::BaseController`); the board
by `task_assignment_minibar_log` (`RequestsController`). A hotel with the first
enabled and the second not is **accepting guest requests into an inbox nobody can
open**. Needs a look at live plan config.

**The index migrations are not `CONCURRENTLY`.** No migration in this repo is, so
they follow convention — but `housekeeping_requests` and `check_out_requests` may
be large enough in production for the table lock to matter. Check row counts
before deploying `20260731090100`.

---

## 6. Tests

707 examples across the requests specs, from 34 at the start.

```bash
bin/test spec/services/hotel_portal \
         spec/requests/hotel_portal/requests \
         spec/requests/hotel_portal/requests_pages_spec.rb \
         spec/models/hotel_portal \
         spec/presenters/hotel_portal --serial
```

The ones worth not breaking:

- `card_reachability_spec.rb` — every card the board draws can be found from its
  own card, per lane, plus a sweep over all of them. This is the one that would
  have caught the cleaning bug years ago.
- `move_spec.rb` — what each lane accepts, that leaving the archive restores
  first, and that a complaint finishes as `resolved`
- `cursor_spec.rb` — the SQL predicate and the Ruby sort agree; plus a walk of a
  lane where **three tables share one timestamp**
- `requests_board_spec.rb` — a busy hotel asks no more questions than a quiet one
- `date_window_spec.rb` — the non-UTC boundary, and a lagging business date
- `requests_pages_spec.rb` — the lane order, that every lane can receive a
  dragged lane, that Checkout receives no cards, the lazy placeholder's layout
  classes, and the move endpoint's streams

Note `bin/test all` flakes on a different one or two system specs each run;
verify with targeted runs. The `front_desk_spec.rb:808` failure the previous
handover called out **now passes** — 61 examples green — so either it was one of
those flakes or something here fixed it. Do not treat it as known-broken.

---

## 7. Before continuing

**Load the board in a browser.** None of this has been seen: not the sideways
scroll, not the drag, not the autoscroll, not the keyboard path, not the
small-screen stack. Two defects were found by looking last time and both were
layout ones that no spec would have caught.

Specifically worth poking:

- Drag a card toward the right edge — the autoscroll zone is 96px and the step
  24px per frame, both picked without watching them.
- Tab to a card, Enter, arrows, Enter.
- Drag a lane by its grip, including Checkout and Archived.
- Narrow below `xl` and confirm the lanes stack and the page scrolls them.
- Archive a card and watch whether the Archived lane and both counts update
  without a reload. That is the whole point of the stream response.
