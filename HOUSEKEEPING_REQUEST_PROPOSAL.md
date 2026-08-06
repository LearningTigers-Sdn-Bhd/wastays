---
title: Housekeeping Tasks page — audit findings and remediation proposal
status: proposal — agreed, no open questions
date: 2026-07-30
scope: Hotel Portal → Front Office → Housekeeping Tasks
---

# Housekeeping Tasks — Audit & Remediation Proposal

Audit of the Hotel Portal **Housekeeping Tasks** page against `DESIGN.md` (UI
contract) and a read-through of its supporting logic. Findings are split into
design violations and logic problems, each with a plain-language column
describing the real-world impact.

Sections 4–6 record decisions taken during review and the agreed plan of work.

## Files reviewed

| Layer | File |
|---|---|
| View | [`app/views/hotel_portal/housekeeping_tasks/index.html.erb`](app/views/hotel_portal/housekeeping_tasks/index.html.erb) |
| View | [`app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb`](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb) |
| Controller | [`app/controllers/hotel_portal/housekeeping_tasks_controller.rb`](app/controllers/hotel_portal/housekeeping_tasks_controller.rb) |
| Controller | [`app/controllers/hotel_portal/requests_controller.rb`](app/controllers/hotel_portal/requests_controller.rb) |
| Controller | [`app/controllers/hotel_portal/checkout_requests_controller.rb`](app/controllers/hotel_portal/checkout_requests_controller.rb) |
| Controller | [`app/controllers/hotel_portal/stay_view/housekeeping_assignments_controller.rb`](app/controllers/hotel_portal/stay_view/housekeeping_assignments_controller.rb) |
| Service | [`app/services/housekeeping_tasks/board_builder.rb`](app/services/housekeeping_tasks/board_builder.rb) |
| Service | [`app/services/housekeeping_tasks/assign_staff.rb`](app/services/housekeeping_tasks/assign_staff.rb) |
| Service | [`app/services/hotel_portal/requests/status_updater.rb`](app/services/hotel_portal/requests/status_updater.rb) |
| Service | [`app/services/rooms/status_resolver.rb`](app/services/rooms/status_resolver.rb) |
| Service | [`app/services/hotel_ops/seed_account_roles.rb`](app/services/hotel_ops/seed_account_roles.rb) |
| Service | [`app/services/stay_view/build_capabilities.rb`](app/services/stay_view/build_capabilities.rb) |
| Service | [`app/services/reports/housekeeping_tasks_export_table.rb`](app/services/reports/housekeeping_tasks_export_table.rb) |
| Presenter | [`app/presenters/hotel_portal/housekeeping_task_room_presenter.rb`](app/presenters/hotel_portal/housekeeping_task_room_presenter.rb) |
| Query | [`app/queries/hotel_portal/active_housekeepers_query.rb`](app/queries/hotel_portal/active_housekeepers_query.rb) |
| Helper | [`app/helpers/hotel_portal/housekeeping_tasks_helper.rb`](app/helpers/hotel_portal/housekeeping_tasks_helper.rb) |
| Model | [`app/models/housekeeping_tasks/task_row.rb`](app/models/housekeeping_tasks/task_row.rb) |
| Spec | [`spec/services/housekeeping_tasks/board_builder_spec.rb`](spec/services/housekeeping_tasks/board_builder_spec.rb) |

---

## 1. Design findings

| # | Finding | Where | In plain terms | DESIGN.md |
|---|---|---|---|---|
| D1 | Page-level `max-w-[1600px] mx-auto pb-10`, then `mx-4 md:mx-0` to compensate | [index:3](app/views/hotel_portal/housekeeping_tasks/index.html.erb:3), [table_view:5,35](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:5) | The page fights the app shell over how wide it should be, so it lines up differently from every other page. | §1 |
| D2 | No semantic tokens — `slate/emerald/amber/rose/blue`, `bg-white`, arbitrary values (`text-[11px]`, `tracking-[0.1em]`, `min-h-[38px]`, `bg-slate-100/80`) | throughout `_table_view`, [presenter:22-30](app/presenters/hotel_portal/housekeeping_task_room_presenter.rb:22) | Colours are hardcoded instead of drawn from the theme. **In dark mode this page stays white** — white text on a white surface. | §2 |
| D3 | Page-local type scale, decorative uppercase + wide tracking everywhere, `font-black` | [table_view:52-60,67](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:52) | Text is heavier, smaller and shoutier than the rest of the portal. Reads like a different product. | §3 |
| D4 | `<h3>` in the empty state with no `<h2>` above it | [table_view:193](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:193) | Heading levels skip a step — screen readers report a broken document outline. | §3, §10 |
| D5 | Five native `select_tag` plus a native `date_field_tag` | [:18](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:18), [:23](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:23), [:28](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:28), [:110](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:110), [:170](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:170) | Raw browser dropdowns and a raw date input, next to styled controls everywhere else in the portal. Most direct rule violation on the page. | §6 |
| D6 | Hand-built table, status badges, collapsible group rows, and search input | whole partial | Four things rebuilt from scratch that already exist as shared components (`PanelsUI::Table`, `Badge`, `Collapsible`, `Input`) — so they drift, and fixes made elsewhere never reach this page. | §5 |
| D7 | ~80 duplicate DOM ids (`assigned_to`, `status`, `redirect_to` repeated once per row, plus a collision with the filter bar) | [:110](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:110), [:169-170](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:169) | Every row's dropdown carries the same name tag. Invalid HTML; breaks label association and any script that looks controls up by id. | §10 |
| D8 | No labels on any filter or row control (search is placeholder-only) | [:13](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:13), [:18](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:18), [:110](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:110), [:170](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:170) | A blind user hears forty identical unnamed dropdowns with no way to tell which room each belongs to. | §10 |
| D9 | Room-type group header is a clickable `<tr>`, no `aria-expanded`/`aria-controls`, not focusable | [:66](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:66) | You can only expand or collapse a room type with a mouse. Keyboard users are locked out. | §10 |
| D10 | Auto-submit on every dropdown change; debounced search re-renders the frame while typing | [:6](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:6), [:110](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:110), [:170](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:170) | The page reloads itself the instant you touch a control — WCAG 3.2.2 "On Input" failure, and it can pull focus mid-typing. | §10 |
| D11 | Truncated task text explained only via a `title=` tooltip | [:151](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:151) | Long task notes are readable only by hovering with a mouse. | §10 |
| D12 | No `aria-live` on the results turbo frame | [:34](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:34) | When filtering changes the results, nothing announces it — a screen reader user never learns the table updated. | §10 |
| D13 | "Assign To" renders only `first_task_request`; "Task Details" and "Task Status" render one block per task | [:107](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:107) | On multi-task rows the columns don't line up, and nothing indicates that the single Assign dropdown governs **all** the room's tasks (see L2). **Resolved by the Take/Release decision — see §4.3.** | §7, §10 |
| D14 | `cached_icon` used where the contract specifies `app_icon` | throughout | Minor, but it bypasses the sanctioned icon helper. | §5 |

---

## 2. Logic findings

| # | Finding | Where | In plain terms | Severity |
|---|---|---|---|---|
| L1 | Tasks are matched by hotel + room number only — room type is never part of the match | [board_builder:104](app/services/housekeeping_tasks/board_builder.rb:104), [:116](app/services/housekeeping_tasks/board_builder.rb:116) | Two room types can each have a room "101". The board merges their tasks. **This is the duplicated "Checkout Room Cleaning" visible on the page today** — one task rendered twice under two different rooms. `Rooms::StatusResolver` *is* room-type scoped, which is why the status column looks right while the task column doesn't. | **High** |
| L2 | Assigning one task assigns *every* active task on that room number, using the same unscoped match | [assign_staff:66](app/services/housekeeping_tasks/assign_staff.rb:66) | Choosing a housekeeper for Penthouse 101 silently reassigns Garden Suite 101's tasks too. This writes to the database, with no warning and no undo. | **High** |
| L3 | `pending` is excluded for housekeeping requests but included for checkout requests | [board_builder:5](app/services/housekeeping_tasks/board_builder.rb:5) | Guest-submitted requests are created as `pending` (`Concierge::SubmitGuestRequest`, and the public API). **They never appear on this board at all** — on the page whose own description promises real-time request management. | **High** |
| L11 | No authorization granularity: the board is not scoped to the current user, and row controls render on `id.present?` alone | [presenter:92](app/presenters/hotel_portal/housekeeping_task_room_presenter.rb:92); no `current_user` anywhere in `BoardBuilder`, presenter, or view | The seeded **Housekeeper** role holds `manage_housekeeping_tasks`, so housekeepers open this page and get the supervisor's god view: every room, every task, and a live dropdown on each. Any housekeeper can assign work to a colleague, unassign someone else, or mark a room complete they never touched. Compounded by L2, one click rewrites the whole room. | **High** |
| L12 | Stay View reaches the same service through a second door | [stay_view/housekeeping_assignments_controller:14](app/controllers/hotel_portal/stay_view/housekeeping_assignments_controller.rb:14) | Stay View calls the same `AssignStaff`, gated on a capability derived from the same permission. Any rule enforced only in the tasks controller is bypassed by using Stay View instead. Enforcement must live in the service. | **High** |
| L5 | The date filter drives room status and booking columns but never filters tasks | [board_builder:104](app/services/housekeeping_tasks/board_builder.rb:104) | Pick last Tuesday and you see last Tuesday's room statuses beside *today's* open tasks. The PDF/Excel/CSV exports inherit this and are filenamed by date, so they look date-scoped and aren't. **Resolved — see §4.5.** | Medium |
| L6 | The model's `active` scope (`archived_at: nil`) is never applied | [board_builder:108](app/services/housekeeping_tasks/board_builder.rb:108) | Tasks someone deliberately archived keep reappearing on the board. | Medium |
| L7 | `assign` redirects to the bare index path; `update_status` preserves the URL | [controller:70](app/controllers/hotel_portal/housekeeping_tasks_controller.rb:70) vs [table_view:169](app/views/hotel_portal/housekeeping_tasks/_table_view.html.erb:169) | Assign a housekeeper and your date, search and filters all reset to defaults. Change a status and they survive. Two behaviours on the same table row. | Medium |
| L8 | Per-room queries, plus every booking the hotel has ever had eager-loaded and re-scanned per room; all filtering done in Ruby; no pagination | [board_builder:142](app/services/housekeeping_tasks/board_builder.rb:142), [:69](app/services/housekeeping_tasks/board_builder.rb:69) | 80 rooms × 5,000 bookings ≈ 400k in-memory comparisons and ~320 queries per page load. Fine on demo data, will crawl in production. The sibling Requests board paginates at 25; this one loads everything. | Medium |
| L9 | `BoardBuilder` spec asserts only that the object responds to `call` (17 lines) | [board_builder_spec.rb](spec/services/housekeeping_tasks/board_builder_spec.rb) | There is effectively no test for the page's core logic — grouping, filtering, the housekeeping/checkout merge, dedup. This is why L1 and L3 shipped unnoticed. | Medium |
| L4 | Page requires `manage_housekeeping_tasks`; the housekeeping status endpoint requires `manage_requests` | [requests_controller:137](app/controllers/hotel_portal/requests_controller.rb:137) | **Downgraded from High after review.** All four seeded roles hold both permissions, so nothing is broken today. It only bites a *custom* role created with one permission and not the other — which is possible, since roles are account-editable. Dissolves entirely under the §4 permission split. | Low |
| L10 | `redirect_to params[:redirect_to]` accepts an arbitrary value | [requests_controller:70](app/controllers/hotel_portal/requests_controller.rb:70), [checkout_requests_controller:48](app/controllers/hotel_portal/checkout_requests_controller.rb:48) | Not an open-redirect vulnerability — Rails 8 defaults block off-host redirects — but a crafted value produces a 500 instead of a graceful failure. Worth allow-listing. | Low |

### Not a finding

Exports are clean on privacy. [`HousekeepingTasksExportTable`](app/services/reports/housekeeping_tasks_export_table.rb:5) emits room, room type, assignee, room status, stay dates and task text — **no guest names or contact details**. Housekeepers being able to export the whole board is therefore not a data-exposure concern.

---

## 3. Root-cause note on L1 / L2

`RoomType#room_numbers` is a per-room-type array, so the same room number can
legitimately exist under multiple room types in one hotel. Every read and write
path on this page must therefore key on **(room_type_id, room_number)**, not
`room_number` alone.

`housekeeping_requests` does carry a `room_type_id` column, but the creation
paths (`Concierge::SubmitGuestRequest`, the public API controller) never
populate it, so it cannot be relied on for existing rows. The durable match has
to resolve room type through the booking's `booking_rooms`, with `room_type_id`
used only as a fast path when present.

`CheckOutRequest` has no room columns at all — its room is derived from
`metadata["room_number"]` or the booking's first room — so the same resolution
applies there.

---

## 4. Decisions

### 4.1 Housekeepers keep the full board, but not full authority

Agreed: a housekeeper **may see every room** — floor staff need the whole
picture — but **may not assign anyone other than themselves**.

### 4.2 Permission split

`manage_housekeeping_tasks` is doing two jobs (dispatch work, and perform work).
It is split in two.

| Slug | Held by | Grants |
|---|---|---|
| `perform_housekeeping_tasks` | Housekeeper | See the whole board, export, **take** unassigned tasks, **release** own tasks |
| `dispatch_housekeeping_tasks` | Hotel Owner, General Manager, Front Desk | Everything above, plus assign/unassign **anyone**, and override a task already held by another person |

Board access is granted by holding **either** permission.

| Capability | perform | dispatch |
|---|---|---|
| See whole board | ✅ | ✅ |
| Export | ✅ | ✅ |
| Take an **unassigned** task | ✅ | ✅ |
| Release a task **they hold** | ✅ | ✅ |
| Take a task **someone else holds** | ❌ | ✅ |
| Assign or unassign **another** person | ❌ | ✅ |

**Clean replacement, no compatibility shim.** There are no hotels in
production, so `manage_housekeeping_tasks` is retired outright rather than
redefined: a migration creates the two new `Permission` rows and drops the old
one, and the role templates in `seed_account_roles.rb` and `db/seeds.rb` are
updated in place. No backfill logic, no two-release contract.

> Had there been live accounts, this would have needed the additive route
> instead — keep the old slug as the perform permission, add dispatch, and
> backfill it to every role holding the old slug *except* `housekeeper` — because
> roles are account-editable and must not be overwritten. Recorded here in case
> the same split is ever needed on a live tenant.

### 4.3 Enforcement lives in the service, and changes the UI control

`HousekeepingTasks::AssignStaff` already receives `current_user`, so the
take-vs-dispatch decision is made **inside the service**. This is required, not
stylistic: Stay View calls the same service (L12), so a controller-level check
would be bypassed by assigning from Stay View instead. One rule in the service
closes both doors and covers any future caller.

This also settles the L2 fan-out question, differently per role:

- **Take** (perform) claims the room's **unassigned** tasks and *skips any held
  by someone else* — a housekeeper can never silently take over a colleague's work.
- **Assign** (dispatch) keeps the existing fan-out across the room and may
  overwrite — the supervisor's prerogative.

And it settles the UI control. A dropdown listing twelve colleagues a housekeeper
cannot pick is the wrong affordance, so:

- **perform-only users** get a per-task **Take / Release** toggle button
- **dispatch users** keep the staff dropdown

Because the button is per task, it stacks alongside the per-task status
controls — which **resolves D13**, the misaligned Assign column, as a side
effect.

### 4.4 Status changes are open to both roles

**Both** `perform_` and `dispatch_housekeeping_tasks` holders may change task
status on any task, assigned to them or not. Status is not gated on assignment.

The two permissions therefore differ on **assignment only**: a housekeeper can
take and release their own work but cannot hand work to a colleague.

Recorded trade-off: the audit log will show status changes made by people who
were never the assignee. This is a deliberate choice — floor flexibility (cover
a room without the ceremony of claiming it first) was judged more valuable than
audit precision. `RoomOperationalAuditLog` still records who performed the
change, so the history remains reconstructible; it simply won't match the
assignee field.

### 4.5 Date filter: single date, "open as of"

The board takes a **single date** and shows tasks **open as of that date**
(option (b) of the two readings). No range, no mode tabs.

Rationale:

- This is a dispatch board — its question is "what needs doing", and almost all
  use is the current day.
- It makes the row internally consistent for the first time. The room-status
  column is already resolved *as of* the selected date via `Rooms::StatusResolver`;
  the task column ignoring the date is exactly what L5 describes. Both halves
  will now answer the same question.
- Historical "what was requested between X and Y" is a **report**, not a board.
  Reports already owns that pattern — range control, export dropdown, month
  grouping, pagination. Duplicating it here would rebuild a whole surface on a
  page that should not own it.

**Tabs were considered and rejected.** A pill-tab mode switch (historical vs
open-as-of) cannot share one date control: "historical" needs a range and
"open as of" needs a single date, so the tab would have to swap the control
beneath it and carry a mode flag through every URL and all three export formats.
Two controls and a mode flag for what is, on a dispatch board, one question.

If historical housekeeping activity is wanted later, add a *Housekeeping
activity* entry under Reports using the existing
[`_preset_report_actions`](app/views/hotel_portal/reports/_preset_report_actions.html.erb)
partial. That partial already supports both shapes — pass `single_date: true`
for an "As of date" picker, or omit it for a range — so neither this page nor a
future report needs a bespoke control.

### 4.6 Deferred

- **L8 (query rewrite + pagination)** — no behaviour change; kept separate so a
  reviewer can attribute any regression. Easier once L1 lands. The §4.5 date
  semantics land inside this phase, since both touch the same query.

---

## 5. Plan of work

Single branch, sequential commits (no stacked branches).

### Phase 1 — Logic pass

| # | Commit | Addresses |
|---|---|---|
| 1 | Permission split: migration (create `perform_`/`dispatch_housekeeping_tasks`, drop `manage_housekeeping_tasks`), role templates, all call sites, `BuildCapabilities`, specs | §4.2, L4 |
| 2 | `AssignStaff`: room-type scoping + take-vs-dispatch enforcement in the service | L1, L2, L11, L12 |
| 3 | `BoardBuilder`: room-type scoping, `pending` made visible, archived excluded | L1, L3, L6 |
| 4 | Preserve filters on the `assign` redirect | L7 |
| 5 | Real `BoardBuilder` and `AssignStaff` specs | L9 |

**Call sites touched by commit 1** — `housekeeping_tasks_controller`,
`checkout_requests_controller`, `requests_controller`,
[`navigation_helper:40`](app/helpers/hotel_portal/navigation_helper.rb:40),
[`build_capabilities:45`](app/services/stay_view/build_capabilities.rb:45),
[`seed_account_roles`](app/services/hotel_ops/seed_account_roles.rb) (4 role
templates), `db/seeds.rb:169,175,176`, plus 6 references across 4 spec files
(`stay_view_spec`, `housekeeping_tasks_spec`, `system/hotel/stay_view_spec`,
`build_capabilities_spec`).

`BuildCapabilities` needs the same split: `manage_housekeeping` becomes the
dispatch-level capability, with a new perform-level capability for take/release.

### Phase 2 — Query rewrite and date semantics

Replace the per-room `find_each` and full-booking scan with one grouped query
keyed on `(room_type_id, room_number)`, push the filters into SQL, and paginate
to match the Requests board. Apply the §4.5 "open as of" date scoping to the
task query in the same pass — it is a `WHERE` clause on the same query, so
splitting it would mean writing the query twice. Addresses **L8** and **L5**.

### Phase 3 — UI rewrite

**Status: done.** Landed in two passes — first the shell and tokens (D1–D3),
then the components, controls and accessibility work below.

Two decisions were taken during the rewrite that §4 had left open:

| # | Question | Decision |
|---|---|---|
| 9 | How do the room columns behave on a multi-task room? | One `<tr>` per task, with `rowspan` on the room columns so they appear once. The task columns line up for the first time, which is what D13 asked for. |
| 10 | What replaces the auto-submitting filter bar (D10)? | An explicit **Apply** button. Strictly correct on WCAG 3.2.2; the instant-filter feel is given up deliberately. |

The Apply decision carried into the row controls too: a `<select>` that submits
on change is the same 3.2.2 failure at row level. Both row controls are now
`PanelsUI::DropdownMenu` menus whose items are `button_to` submissions — an
explicit activation rather than a change event, which also removes the ~80
duplicate ids (D7) outright, since there is no repeated field name left.

`aria-controls` on the group toggle names the group's row ids rather than a
wrapping element: `PanelsUI::Table` renders one `<tbody>`, so a room-type group
is not a DOM subtree that could be wrapped.

The results `aria-live` region (D12) sits *outside* the turbo frame, fed by a
small `results-announcer` Stimulus controller on `turbo:frame-load`. A live
region inside the frame is destroyed and recreated by the swap, so it would
never announce; making the frame itself the live region would announce the
whole table.


One rewrite of `_table_view.html.erb` against `PanelsUI::Table`, `Badge`,
`SelectMenu` / `Combobox`, `DatePicker`, `Collapsible` and `Input`, using
semantic tokens throughout, and removing the page-level width cap in
`index.html.erb`. Clears **D1–D14** in a single pass; D7 (duplicate ids) and D2
(missing dark theme) resolve as side effects of using shared components and
tokens.

The brief is now concrete: per-task rows, Take/Release for perform users, staff
dropdown for dispatch users, status editable by both roles (§4.4), and a single
"As of date" picker via the shared reports partial (§4.5).

**Reference implementation:**
[`app/views/hotel_portal/reports/outstanding_balance.html.erb`](app/views/hotel_portal/reports/outstanding_balance.html.erb).
It uses `PanelsUI::Table` with `density: :compact` and `header_style: :sentence`,
semantic tokens throughout, `<section aria-labelledby>` regions, and the shared
`_preset_report_actions` / `_export_dropdown` partials. Matching that file is
the target — this is a port, not a fresh design.

### Also fold in when convenient

**L10** — done. `safe_redirect_target` on `HotelPortal::BaseController` accepts
only a path within this app, so a crafted value falls back to the page's default
instead of raising. Applied to all seven `?redirect_to` sites across
`requests_controller` and `checkout_requests_controller`.

---

## 6. Decision log

No open questions. Phase 1 is ready to start.

| # | Question | Decision |
|---|---|---|
| 1 | Should housekeepers see the whole board? | Yes — floor staff need the full picture |
| 2 | Should housekeepers assign other people? | No — self only (take / release) |
| 3 | Is `manage_housekeeping_tasks` doing two jobs? | Yes — split into `perform_` and `dispatch_housekeeping_tasks` (§4.2) |
| 4 | Migrate additively or replace cleanly? | Replace cleanly — no hotels in production, so no backfill or compat shim (§4.2) |
| 5 | Where is the self-assign rule enforced? | Inside `AssignStaff` — Stay View shares the service, so a controller check would be bypassable (§4.3) |
| 6 | Can perform-only users change status? | Yes, on any task; the two roles differ on assignment only (§4.4) |
| 7 | What does the date filter mean? | Single date, tasks open **as of** that date (§4.5) |
| 8 | Add historical/open-as-of mode tabs? | No — the two modes need different date controls; history belongs in Reports (§4.5) |
