# Booking Actions Sheet — Handoff

> Purpose: hand this to another agent to continue the Offcanvas → `PanelsUI::Sheet`
> migration described in `BOOKING_ACTIONS_SHEET_MIGRATION.md`.
>
> **Done & green so far:** (1) Phase-1 prep + Audit Trail pilot, (2) the entire
> **booking-creation family** (New / Quick / Walk-in / Backdated), including every
> launcher across front desk, bookings index, and Stay View, (3) **Show Booking
> summary + group Print/Send**, which also established the **two-frame stacking
> pattern** and the `click_in_overlay` system-spec helper, (4) **Cancellation**, and
> (5) **guest management + structured internal notes**, and (6) the complete
> **stay-editing family** (dates, room assignment/move, rate, and booking details).

## Stack / conventions (must follow)

- Rails 8 · Ruby 3.4.7 · PostgreSQL. No-build: Import Maps (no Node). Tailwind via gem. No Redis.
- Business logic lives in `app/services/<domain>/`. Controllers only orchestrate authorization, input, rendering, responses. **Do not copy business rules from legacy controllers.**
- UI: PanelsUI ViewComponents + semantic tokens. Read `DESIGN.md` before UI work. No native selects.
- `current_hotel` in controllers. Run app: `./bin/dev` (NOT `bin/rails s`). Needs `RAILS_MASTER_KEY`/`config/master.key`.
- Tests: `bin/test <domain>` (e.g. `bin/test bookings`). Single: `bin/test spec/x_spec.rb[:12]`. Lint: `bin/rubocop`.
- **Isolation mandate:** new code must not use `offcanvas`, `drawer`, or generic `overlay` names, and must not call legacy controllers/helpers/JS/views. Duplicate shared logic (or copy leaf partials) rather than depend on the legacy implementation.

## The two systems

**Legacy (Offcanvas) — stays running until each action is migrated:**
- Controllers: `app/controllers/hotel_portal/bookings/transactions/**` and `.../bookings/show/actions/**`.
- Concern `offcanvas_transaction_completion.rb`; frame `offcanvas_drawer` (`shared/_offcanvas_drawer.html.erb` + `offcanvas_controller.js`); custom `Turbo.StreamActions.complete_offcanvas` in `application.js`.

**New (Sheet) — target:**
- Namespace `HotelPortal::Bookings::Actions`, view root `app/views/hotel_portal/bookings/actions/`.
- Renders into `PanelsUI::Sheet` (`app/components/panels_ui/sheet.rb`), a native `<dialog>` (focus trap, inertness, focus restore, reduced-motion, theming for free).
- Two frames: `booking_action_sheet` (primary) + `booking_action_sheet_secondary` (stacked). Completion action `complete_sheet`.

| Concept | Legacy | New |
|---|---|---|
| Turbo Frame | `offcanvas_drawer` (+ `offcanvas_drawer_secondary`) | `booking_action_sheet` (+ `booking_action_sheet_secondary`) |
| Completion stream action | `complete_offcanvas` | `complete_sheet` |
| Completion concern | `OffcanvasTransactionCompletion` | `BookingActionCompletion` |
| Sheet-open JS | `offcanvas_controller.js` | `panels-ui--sheet-frame` (reused, existing) |
| View root | `bookings/transactions`, `bookings/show/actions` | `bookings/actions` |

## The canonical pattern (frame-loaded Sheet) — copy this

Precedent: `nearby_attractions` (+ `panels-ui--sheet-frame`). Also how Audit Trail and Creation are wired.

1. Two **empty** frames live globally in `app/views/layouts/_hotel_shell.html.erb`: `turbo_frame_tag "booking_action_sheet"` and `turbo_frame_tag "booking_action_sheet_secondary"`.
2. A **launcher** is a plain link/menu-item with `data: { turbo_frame: "booking_action_sheet" }` pointing at the action route. **No `offcanvas_variant`** — size is decided by the view, not the launcher (see "Sizing" below). The frame it targets is the **stacking knob** (see "Stacking / multistep" below).
3. The action view renders through the shared shell, which wraps content in `turbo_frame_tag <frame>` → `<div data-controller="panels-ui--sheet-frame">` → `PanelsUI::Sheet`. `<frame>` defaults to the **requesting** frame (`turbo_frame_request_id`, falling back to `booking_action_sheet`), so one view works in any frame. On connect, `panels-ui--sheet-frame` (`app/javascript/controllers/panels_ui/sheet_frame_controller.js`) auto-opens the `<dialog>` and clears **its own** frame on the native `close` event (`element.closest("turbo-frame")` — frame-agnostic).
4. Controllers render `layout: false`.
5. **Read-only** actions need nothing more. **Mutating** actions complete via `complete_booking_action` (emits `complete_sheet` → close + navigate to a validated destination). On validation failure, re-render the form into the frame with `:unprocessable_content` (the `<dialog>` reconnects/reopens with submitted values + errors).

Shared shell for booking-scoped actions: `app/views/hotel_portal/bookings/actions/shared/_sheet.html.erb`
(`render "hotel_portal/bookings/actions/shared/sheet", id:, title:/aria_label:, size:, side:, dismissible:, footer: do … end`).
The creation family does **not** use this shell (its form spans body+footer); it renders `PanelsUI::Sheet` directly.

## Shared infrastructure (Phase-1 prep — reused by every action)

- **Route scope** in `config/routes.rb` (next to `booking-transactions`):
  `scope "booking-actions", as: :booking_action, module: "bookings/actions"`. Route name prefix is singular: `hotel_booking_action_*`.
- **`app/controllers/concerns/booking_action_completion.rb`** — `complete_booking_action(destination:, notice:, html_status:)`, `render_booking_action_completion` (emits `complete_sheet` targeting `booking_action_sheet`), `booking_action_return_to(fallback:)` (same-origin / `/hotel/<param>/` validation, duplicated from the offcanvas concern for isolation).
- **`app/controllers/hotel_portal/bookings/actions/base_controller.rb`** — for **booking-scoped** actions (`:booking_id`): `authorize_manage_bookings!` + `set_booking` + `set_return_to` + `complete_action`.
- **`Turbo.StreamActions.complete_sheet`** in `app/javascript/application.js` — closes the sheet via its `panels-ui--sheet` controller (native dialog restores focus; `panels-ui--sheet-frame` clears the frame), then `Turbo.visit(url, { action: "replace" })` after the exit transition.
- **Global frame** `turbo_frame_tag "booking_action_sheet"` in `_hotel_shell.html.erb`.

## Sizing contract (important — this is the DRY win)

Modal size/side is decided **centrally by action type in the action's view**, never by the launcher.
Launchers only set `data-turbo-frame="booking_action_sheet"`. This deliberately killed the scattered
per-entry-point offcanvas variants (`right`, `fullscreen-bottom`, `compact-right`). Current creation mapping
(in `bookings/actions/booking_creations/_form.html.erb`):

- **Quick** → `side: :right, size: :lg`
- **New / Walk-in / Backdated** → `side: :bottom, size: :full`

When migrating a new action family, follow the same rule: put the size on the Sheet in the view.

## Stacking / multistep — the frame knob (important)

A sheet is a native `<dialog>`; the PanelsUI overlay stack (`support/overlay.js`:
`activeOverlays` / `isTopOverlay` / ref-counted `lockScroll`) already supports
**stacking** — several dialogs coexist in the top layer, only the top one answers
Escape/backdrop, and closing it reveals the one beneath (LIFO). See the showcase
`_sheet_preview.html.erb` / `spec/system/panels_ui/sheet_spec.rb`.

Because the shared shell renders into the **requesting** frame (see canonical
pattern #3), **the launcher's `data-turbo-frame` is the only knob**:

| Launcher targets… | Result |
|---|---|
| `booking_action_sheet` | top-level sheet |
| `booking_action_sheet_secondary` | **stacks** above the primary (primary stays open, inert underneath) |
| the frame already showing a sheet | **replaces** it (multistep) |

Rules of thumb:
- One action = one lazy controller/route/view. It does **not** know whether it's
  top-level or stacked — that's decided by whoever launches it. This is what lets
  the same action open **standalone** (primary frame) or **stacked** (secondary
  frame) — e.g. group Print/Send stacks over the summary but is also launchable on
  its own.
- Prefer **stacking** for a drill-down you can return from (native focus
  restoration walks the stack back for free). Avoid **replace/multistep** for a
  drill-down off a *stateful* sheet — replacing discards the parent's state (this
  is why an earlier replace-in-frame attempt with a `navigate()` hack was reverted).
- Depth today is 2 frames (primary + secondary). Add another `_secondary`-style
  frame only if a real 3-deep flow appears.
- Close a stacked child with a `data-action="panels-ui--sheet#close"` control
  (closes the top overlay, reveals the parent). Its `sheet-frame` clears the child
  frame; the parent is untouched.

## Shipped #1 — Audit Trail (read-only pilot)

- Route `get "audit-trail/:booking_id" → audit_trails#show`.
- `bookings/actions/audit_trails_controller.rb < BaseController` — **read-only exception**: `skip_before_action :authorize_manage_bookings!`, instead `view_bookings` + `full_audit_trail` feature (via `require_feature!` from `PlanGated`).
- View renders shared `_sheet` (`aria_label`, `size: :lg`) whose body is the **existing, unchanged** `booking_control_panels/audit_trails/_booking_audit_log` partial with `closeable: false`.
- Launchers: the 5 front-desk room-card partials (`front_desk/_{bookings,arrivals,in_house,checkout,departures}_rooms.html.erb`).
- Specs: `spec/requests/hotel_portal/bookings/actions/audit_trails_spec.rb`; system open/close in `booking_control_panel_phase6_spec.rb`.

## Shipped #2 — Booking-creation family (New / Quick / Walk-in / Backdated)

**Key discovery:** 7 of the 9 `new_booking/partials/*` were **dead code** (a superseded `booking-calc` form): `_header`, `_footer`, `_stay_details`, `_guest_information`, `_select_room`, `_errors`, `_guest_change_modal`. The live form only uses `_room_rate_table` + `_payment`, driven by the `booking-room-rows` Stimulus controller. **These 7 dead partials are a pending cleanup — untouched.**

- Routes (GET+POST): `new-booking`, `quick-booking`, `walk-in-check-in`, `backdated-check-in` in the `booking-actions` scope.
- **`bookings/actions/booking_creation_base_controller.rb`** — creation has **no `:booking_id`**, so it does NOT use `BaseController`. Ports the builders (`build_booking`, `create_staff_booking`, `staff_room_rows`, `booking_params`, `model_booking_params`), `authorize_manage_bookings!`, `include BookingActionCompletion`. Success → `complete_new_booking` (→ new booking's control panel). Failure → `render_new_booking_failure` (turbo-updates the `booking_action_sheet` frame with `_form`, `:unprocessable_content`).
- Thin controllers: `new_bookings`, `quick_bookings`, `walk_in_check_ins`, `backdated_check_ins` (creation branch only — the review-no-show / existing-booking backdated stays on legacy `transactions`).
- Views under `bookings/actions/booking_creations/`: `show.html.erb` (frame wraps `_form`), `_form.html.erb` (Sheet chrome; `booking-room-rows` div wraps the `<form id="manual_booking_form">`; submit lives in the Sheet **footer** via `form="manual_booking_form"`, nearby_attractions-style), and self-contained copies `partials/_room_rate_table.html.erb` + `partials/_payment.html.erb`.
- Launchers repointed to the sheet:
  - `front_desk/index.html.erb`, `bookings/index/index.html.erb` (quick + walk-in + backdated).
  - Stay View: `stay_view/board/_toolbar.html.erb` (Walk-in + Add booking) and `stay_view_helper.rb` (`stay_view_cell_actions` + `stay_view_room_slot_actions` — backdated/walk-in/new).
- **Stay View mechanism:** action hashes carry intent-specific frame data. Creation and stay-editing actions target `booking_action_sheet`; remaining legacy housekeeping/room-block actions retain `stay_view_action_data` and the Offcanvas. Do not change the legacy helper globally until those remaining callers migrate.
- Specs: `spec/requests/hotel_portal/bookings/actions/booking_creations_spec.rb` (GET all 4 into the sheet incl. side assertions; POST create→redirect; walk-in create→checked-in; Turbo→`complete_sheet`; invalid re-render; backdate-reason guard; permission block). Updated `stay_view_spec.rb` create scenarios to assert on `#booking-creation-sheet`. Updated legacy-launcher assertions in `manual_bookings_spec.rb`, `bookings_spec.rb`, `front_desk_spec.rb`.
- Legacy `transactions` create controllers/views are now **zero-caller (dead but present)** for rollback.

**Known minor regression:** Quick's "More options → Full" is a plain `booking_action_sheet` frame-reload link (drops the legacy JS value-preservation on switch).

## Shipped #3 — Show Booking summary + group Print/Send (first stacking case)

- Routes: `get "show-booking/:booking_id" → summaries#show` and `get "show-booking/:booking_id/print-send" → documents#show` in the `booking-actions` scope.
- **`bookings/actions/overview_base_controller.rb < BaseController`** — read-only base for both: `skip_before_action :authorize_manage_bookings!` + `authorize_view_bookings!`, eager-loads the booking (and, for groups, the whole group) with folios/rooms/guests, builds `@presenter` (`BookingPresenter`) + `@panel_presenter` (`BookingControlPanelPresenter`).
- **`summaries_controller.rb`** — the booking summary sheet (`#booking-summary-sheet`, right/lg). Standalone bookings show a Print/Send **dropdown** (`_print_send_menu`); group bookings show a Print/Send **link** targeting `booking_action_sheet_secondary` → stacks the documents sheet.
- **`documents_controller.rb`** — group Print/Send documents (`#booking-group-documents-sheet`, right/lg), rendered via the shared shell so it lands in whichever frame launched it. Non-group bookings redirect back to the summary with an alert. "Back to booking summary" is a `panels-ui--sheet#close` button (closes the stacked child, reveals the summary). **This is the reference implementation for stacking + standalone.**
- Launcher: Stay View Room-View booking item now opens the summary sheet (`stay_view_helper#stay_view_booking_action_data` = `{ turbo_frame: "booking_action_sheet" }`).
- Specs: `spec/requests/hotel_portal/bookings/actions/booking_overviews_spec.rb` (summary content + secondary-frame link; documents rendered into the secondary frame *and* standalone into the primary; close-button shape; non-group redirect). System stacking + focus-restoration flow in `stay_view_spec.rb` ("opens group documents…").

## Shipped #4 — Cancellation

- Route: `match "cancel-booking/:booking_id" → cancellations#show` (GET+POST).
- `bookings/actions/cancellations_controller.rb` uses `Bookings::TransitionStatus`, preserves group targeting, rerenders invalid forms in the requesting frame, and completes primary or stacked Sheets correctly.
- Launchers: booking-control-panel summary, Stay View lifecycle actions, and the booking summary Sheet (secondary frame).
- Specs: `spec/requests/hotel_portal/bookings/actions/cancellations_spec.rb` plus the browser flow in `booking_control_panel_phase6_spec.rb`.

## Shipped #5 — Guest management + structured internal notes

- Routes/controllers: `bookings/actions/guests_controller.rb` and `internal_notes_controller.rb`; guest add/remove and all note interactions use Sheets. Guest editing intentionally remains the existing inline Guest Details workspace, but now submits to the new isolated controller with an HTML 303 response.
- Guest services: new `BookingGuests::Add` and `BookingGuests::UpdatePrimary`; existing `UpdateSnapshot`, `Remove`, and `Bookings::SetPrimaryGuest` are reused. The missing-primary fallback no longer reports success after a BIBO validation rollback.
- Guest UI: Add Guest and Remove Guest use `booking_action_sheet`; Make Primary is now reachable from the active additional-guest footer. The inline form uses PanelsUI selection/date-time controls and retains snapshot vs reusable-profile save behavior.
- Note services: `Bookings::CreateBookingNote`, `UpdateBookingNote`, and `DeleteBookingNote` own mutation + audit transactions. Existing edit-history and no-op audit behavior is preserved.
- Notes UI: structured `BookingNote` records are now visible in Booking Details. Add/edit/history/delete use Sheet routes; successful mutations immediately replace the notes section and emit `complete_sheet`. This is separate from the scalar `Booking#internal_notes` field used by creation/registration-card workflows.
- Removed after caller count reached zero: `bookings/show/actions/**`, old guest/note REST controllers/routes, the shared legacy guest/note confirmation, and dormant guest list/drawer partials.
- Specs: new guest/note service and request specs, plus end-to-end guest add/remove and note add/edit/history/delete browser flows in `booking_control_panel_phase6_spec.rb`.

## Shipped #6 — Stay editing (dates / room / rate / booking details)

- Routes (GET+PATCH): `edit-dates/:booking_id`, `edit-room/:booking_id`, `edit-rate/:booking_id`, and `edit-booking/:booking_id`, exposed as `hotel_booking_action_edit_{dates,room,rate,booking}_path`.
- Intent-scoped controllers: `BookingDatesController`, `RoomAssignmentsController`, and `RateChangesController` include the shared `StayEditingForm` concern; `BookingEditsController` owns guest/contact/source/guarantee fields. Controllers orchestrate `Bookings::UpdateStayService` and re-render the requesting Sheet frame with 422 errors.
- Date changes alone are group-aware through `Bookings::UpdateGroupStay`. Room, rate, and booking-detail edits remain per-booking so a Sheet never silently mutates siblings.
- Stay View drag/resize proposals now open the matching Sheet without mutation. Room moves carry proposed room and dates into `RoomAssignmentsController`; date resize proposals go to `BookingDatesController`. `Bookings::ValidateStayProposal` performs the non-mutating room/date check.
- Rate selection is centralized in `Bookings::RateSelection`. Standard plans use the plan ID token; walk-in/corporate tiers use `tier_<tier>_<plan_id>`. `UpdateStayService` persists the selected tier in each nightly snapshot, preserves manual overrides for date-only changes, and clears them for an explicit rate change.
- Dynamic room/rate choices use PanelsUI select menus. `panels-ui--select-menu#replaceOptions` keeps the hidden native select and styled listbox synchronized when room type or stay dates change.
- Launchers in the booking summary, booking control panel, and Stay View now target `booking_action_sheet` or the secondary frame as appropriate. The legacy amend-stay, timeline-edit, Stay View move/date controllers, views, routes, and `timeline_move_form_controller.js` were removed after their caller count reached zero.
- Stay View viewport restoration now persists scroll/focus across Sheet completion reloads. `data-viewport-settled` marks completion of the single initial restore/center frame; Sheet close clears a consumed focus request so Escape does not leak stale focus into a later refresh. Do not add a second `turbo:load` restore path.
- Specs: request coverage in `spec/requests/hotel_portal/bookings/actions/{booking_dates,booking_edits,rate_changes,room_assignments}_spec.rb`, service coverage for rate selection/update behavior, and keyboard/drag/resize/focus/scroll browser coverage in `spec/system/hotel/stay_view_spec.rb`.

## Verification status

Pre-stay-editing baseline: `bin/test bookings` → 580 examples, all pass; `booking_control_panel_phase6_spec.rb` → 11 examples, 0 failures, 2 pre-existing pending; Rubocop clean.

Latest stay-editing verification: the original keyboard/focus/scroll flake passed 30 repeated runs, the selective-refresh scroll case passed 10 repeated runs, related focused Stay View examples passed, and `spec/system/panels_ui/sheet_spec.rb` passed 8/8. `git diff --check` was clean. A full post-migration domain/CI run has not yet been recorded in this handoff.

## Next actions (recommended order)

1. Check-in and exception lifecycle (check in/edit time, existing-booking backdated check-in, undo check-in, mark no-show, reinstate).
2. Late-checkout review, then full checkout last because it coordinates folios, early departure, audit blockers, groups, deposits, and side effects.
3. Delete each remaining legacy action once its caller count hits zero; retire the offcanvas infrastructure last.

## Acceptance checklist (every migrated action)

- Opens inside `booking_action_sheet`; accessible title or `aria_label`; intentional initial focus.
- Escape / dismiss / completion all close cleanly and restore focus.
- Invalid forms stay open, preserve submitted values, errors announced.
- Group target selection preserved where applicable.
- Completion navigates to the correct destination; direct HTML request has a redirect fallback.
- Size set on the Sheet in the view (not the launcher); works mobile/desktop, reduced-motion, light/dark.
- No `offcanvas`/`drawer`/`overlay` names in new files. Request spec + (for interactive flows) a `:js` system spec.

## Gotchas

- `PanelsUI::Sheet.new` raises unless `title:` or `aria_label:` is given. Use `aria_label:` when the body partial already renders its own heading (avoids a duplicate visible title).
- Turbo-format render pitfall: `render template: "…show", layout: false` has no `.turbo_stream` variant → `MissingTemplate` on a Turbo submit. For failure re-renders use a `respond_to` that renders `turbo_stream.update("booking_action_sheet", partial: "…/form")` (see `render_new_booking_failure`).
- Native `<dialog>` restores focus to whatever was focused at `showModal()`; rely on it for ordinary and stacked closes. Stay View completion is the exception because `complete_sheet` performs a page visit: its viewport controller persists the launcher ID and scroll snapshot across that reload.
- **System-spec clicks inside an open sheet must use `click_in_overlay`** (`spec/support/overlay_interaction_helper.rb`), not `click_link`/`click_button`/`.click`. cuprite's coordinate hit-testing intermittently misses controls in the `<dialog>` top layer — a normal click reports success yet never lands, so the flow silently stalls (~40–60% flake). The helper focuses the element (so focus restoration still works) then dispatches the DOM click. Use it **only** inside an open modal dialog; elsewhere keep standard Capybara actions (they also verify clickability). Reads/assertions inside a sheet need no change. Close via Escape still uses `find("dialog#…").send_keys(:escape)`.
- The shared `_sheet` renders into `turbo_frame_request_id` (default `booking_action_sheet`). A request spec hitting the route **without** a `Turbo-Frame` header gets the primary frame; pass `headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }` to assert the stacked case.
- `require_feature!(slug)` is in `PlanGated` (app-wide). Feature gating in specs: `hotel.update!(plan: create(:plan))` + `create(:plan_feature, plan: hotel.plan, feature: create(:feature, feature_group: create(:feature_group), slug: "…"), enabled: true)`.
- Routing uses `scope … module:` (not `namespace`); route prefixes singular (`hotel_booking_action_*`).
- Authorization is direct permission checks raising `Pundit::NotAuthorizedError` (rescued app-wide to a root redirect + "not authorized" flash) — no booking Pundit policy.
- Creation `staff_room_rows` accepts either `booking[rooms][…]` or top-level `booking[room_type_id]/[room_number]`; specs use the top-level slice form.
