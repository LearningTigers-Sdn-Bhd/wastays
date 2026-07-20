# Booking Actions Sheet — Handoff

> Purpose: hand this to another agent to continue the Offcanvas → `PanelsUI::Sheet`
> migration described in `BOOKING_ACTIONS_SHEET_MIGRATION.md`.
>
> **Done & green so far:** (1) Phase-1 prep + Audit Trail pilot, (2) the entire
> **booking-creation family** (New / Quick / Walk-in / Backdated), including every
> launcher across front desk, bookings index, and Stay View.

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
- Frame `booking_action_sheet`; completion action `complete_sheet`.

| Concept | Legacy | New |
|---|---|---|
| Turbo Frame | `offcanvas_drawer` | `booking_action_sheet` |
| Completion stream action | `complete_offcanvas` | `complete_sheet` |
| Completion concern | `OffcanvasTransactionCompletion` | `BookingActionCompletion` |
| Sheet-open JS | `offcanvas_controller.js` | `panels-ui--sheet-frame` (reused, existing) |
| View root | `bookings/transactions`, `bookings/show/actions` | `bookings/actions` |

## The canonical pattern (frame-loaded Sheet) — copy this

Precedent: `nearby_attractions` (+ `panels-ui--sheet-frame`). Also how Audit Trail and Creation are wired.

1. An **empty** `turbo_frame_tag "booking_action_sheet"` lives globally in `app/views/layouts/_hotel_shell.html.erb`.
2. A **launcher** is a plain link/menu-item with `data: { turbo_frame: "booking_action_sheet" }` pointing at the action route. **No `offcanvas_variant`** — size is decided by the view, not the launcher (see "Sizing" below).
3. The action view wraps content in `turbo_frame_tag "booking_action_sheet"` → `<div data-controller="panels-ui--sheet-frame">` → `PanelsUI::Sheet`. On connect, `panels-ui--sheet-frame` (`app/javascript/controllers/panels_ui/sheet_frame_controller.js`) auto-opens the `<dialog>` and clears the frame on the native `close` event.
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
- **Stay View mechanism (do this pattern for future stay-view migrations):** `stay_view_action_data` (offcanvas `compact-right`) is shared by many *non-migrated* actions (moves, dates, housekeeping, room blocks) — **do not change it globally**. Added `stay_view_create_booking_data` (`{ turbo_frame: "booking_action_sheet" }`), set it on the create action hashes, and changed only those two builders' final `.map` to `action.fetch(:data, stay_view_action_data)` so per-action sheet data isn't clobbered.
- Specs: `spec/requests/hotel_portal/bookings/actions/booking_creations_spec.rb` (GET all 4 into the sheet incl. side assertions; POST create→redirect; walk-in create→checked-in; Turbo→`complete_sheet`; invalid re-render; backdate-reason guard; permission block). Updated `stay_view_spec.rb` create scenarios to assert on `#booking-creation-sheet`. Updated legacy-launcher assertions in `manual_bookings_spec.rb`, `bookings_spec.rb`, `front_desk_spec.rb`.
- Legacy `transactions` create controllers/views are now **zero-caller (dead but present)** for rollback.

**Known minor regression:** Quick's "More options → Full" is a plain `booking_action_sheet` frame-reload link (drops the legacy JS value-preservation on switch).

## Verification status

`bin/test bookings` → all pass. `stay_view_spec.rb` (JS) → 24 pass, 2 pre-existing pending. Rubocop clean. No `offcanvas` in any new file.

## Next actions (recommended order)

1. **Cancellation** (doc rollout step 3 — proves invalid-form + completion + group targeting). Two legacy pieces: `Transactions::CancelBookingsController#show` (renders form) + `Bookings::CancellationsController#create` (POST, runs `Bookings::TransitionStatus`, supports group batch-cancel via the `GroupLifecycleTargeting` concern + `group-lifecycle-targets` Stimulus controller + `shared/_group_target_selector` partial — all drawer-agnostic, reuse as-is). Build one `bookings/actions/cancellations_controller.rb` with `show` + `create`; add a request spec asserting the `complete_sheet` action-tag shape (mirror `transactions_spec.rb`: `action="complete_sheet"`, target `booking_action_sheet`, CGI-escaped destination) and the invalid-form branch. **Launchers are heterogeneous** — some live inside unmigrated Edit/Show-Booking offcanvas views; repoint only the standalone-page ones (`_summary_row`, Stay View) and leave the embedded ones on legacy.
2. Show Booking + group Print/Send.
3. Guest + internal-note management (`bookings/show/actions/**`).
4. Stay-editing (edit booking, amend stay, change room/timeline, dates).
5. Check-in / checkout lifecycle (incl. the existing-booking backdated flow).
6. Delete each legacy action once its caller count hits zero; retire the offcanvas infra last.

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
- Native `<dialog>` restores focus to whatever was focused at `showModal()` — do **not** hand-roll focus restoration.
- `require_feature!(slug)` is in `PlanGated` (app-wide). Feature gating in specs: `hotel.update!(plan: create(:plan))` + `create(:plan_feature, plan: hotel.plan, feature: create(:feature, feature_group: create(:feature_group), slug: "…"), enabled: true)`.
- Routing uses `scope … module:` (not `namespace`); route prefixes singular (`hotel_booking_action_*`).
- Authorization is direct permission checks raising `Pundit::NotAuthorizedError` (rescued app-wide to a root redirect + "not authorized" flash) — no booking Pundit policy.
- Creation `staff_room_rows` accepts either `booking[rooms][…]` or top-level `booking[room_type_id]/[room_number]`; specs use the top-level slice form.
