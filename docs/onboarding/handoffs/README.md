# Onboarding phase handoffs — shared context

Read this file first, then the handoff for the phase you are implementing. Each phase is
designed to be picked up by a fresh session with no prior conversation history.

Authoritative sources, in order:

1. `docs/onboarding/FLOW_DECISIONS.md` — product behaviour
2. `docs/onboarding/DESIGN_DECISIONS.md` — presentation
3. `DESIGN.md` (root) — portal UI contract, PanelsUI components, semantic tokens
4. `docs/onboarding/PLAN.md` — phase scope and deliverables
5. `docs/onboarding/IMPLEMENTATION_MAP.md` — verified inventory of existing domain code

`CLAUDE.md` rules apply throughout: business logic in `app/services/<domain>/`, one
verb-named class per file; reuse before adding; align on approach before writing code.

## Status as of 2026-08-13

Phases 0–9 are complete. Phase 10 is the next slice — do not start a phase whose
prerequisite section is still a placeholder.

**Start at `REMAINING_WORK.md`** — it is the verified state of the branch and the scope of
phases 10–13, and it supersedes any phase file it disagrees with.

| Phase | Sections | State |
|---|---|---|
| 4 | `property_profile`, `roles_permissions`, `staff_setup` | Complete |
| 5 | `taxes_fees`, `room_revenue` | Complete |
| 6 | `rooms` | Complete |
| 7 | `rates_availability` | Complete |
| 8 | `extra_charges`, `discounts`, `payment_methods`, `corporate_accounts` | Complete |
| 9 | `channel_manager` | Complete as rescoped — credential intake only |
| 10 | `review` + submission | Next. `REMAINING_WORK.md`, then `PHASE_10_REVIEW_SUBMISSION.md` |
| 11–13 | admin launch, enforcement, legacy cleanup | `REMAINING_WORK.md` |

Phases are strictly sequential: `section_catalog.rb` encodes a prerequisite chain, and
`UpdateSection` refuses any transition whose prerequisites are unresolved. Do not attempt
two phases in parallel.

## Branch and commit convention

All onboarding phases live on a single branch as sequential commits — not stacked
branches. The current branch is `feat/onboarding-shell`. Confirm with the user whether to
continue on it or cut a fresh branch off `main` before committing.

## The established pattern (from Phase 4 — follow it)

### Section registry

`app/services/onboarding/section_catalog.rb` already declares all 13 sections with
`key`, `phase`, `required`, `route_name`, and `prerequisites`. Your phase's sections
already exist there. Change it only if the plan requires a new section or a changed
required/optional decision — and say so explicitly in the commit.

### Routing

Three routes serve every section (`config/routes.rb:288-290`):

```ruby
get   "onboarding",              to: "onboarding#index",  as: :onboarding
get   "onboarding/:section_key", to: "onboarding#show",   as: :onboarding_section
patch "onboarding/:section_key", to: "onboarding#update"
```

Nothing in phases 6–10 should need new top-level onboarding routes for the main
save/continue flow. Sub-resource routes (adding a room type, uploading a photo,
retrying a channel connection) are the legitimate exception — nest them under the
`hotel` scope and keep them reachable from the onboarding layout.

### Controller

`app/controllers/hotel_portal/onboarding_controller.rb` is the single entry point. Its
current shape:

- `before_action :authorize_onboarding!` → `HotelPolicy#update?`
- `before_action :build_navigation` → `Onboarding::NavigationState`
- `before_action :redirect_locked_section` → bounces unavailable sections to the resume page
- `#prepare_section` → a `case` on `@current_entry.definition.key` building per-section ivars
- `#update` → `pending_review?` guard, then `implemented_section?` branch or the placeholder path
- `IMPLEMENTED_SECTIONS` → the constant both `implemented_section?` and `show.html.erb` read,
  so the controller and the view cannot disagree about which sections are real

**Your phase's work here:** add your section keys to `IMPLEMENTED_SECTIONS`, extend the
`case` in `prepare_section` and the one in `update_implemented_section`, and route each key
to its own `Onboarding::*` service.

The controller is already long. If your phase adds substantial per-section branching,
extract per-section handling rather than growing the `case` indefinitely — but do not
restructure the whole controller as a side quest.

### Services

One verb-named class per file in `app/services/onboarding/`. Existing examples to copy:

- `save_property_profile.rb` — form-backed save with `complete:` flag
- `save_staff_drafts.rb` — collection save, validation, transaction, `UpdateSection` inside
- `confirm_role_presets.rb` — explicit confirmation
- `decide_no_additional_staff.rb` — explicit skip decision

Shape: `Result = ApplicationResult.define(...)`, `initialize(hotel:, actor:, ..., complete:)`,
`#call` returns success/failure, and the section transition happens **inside the same
transaction** as the domain write, rolling back on failure. Copy `SaveStaffDrafts` for
anything collection-shaped.

### Section state transitions

Always go through `Onboarding::UpdateSection` (`app/services/onboarding/update_section.rb`).
It enforces prerequisites, refuses to skip required sections, writes `completed_at` /
`skipped_at` / `decision_metadata`, and appends an `onboarding_audit_events` row.

States: `not_started`, `in_progress`, `complete`, `skipped`, `needs_attention`.

**Do not write `onboarding_sections` rows directly.**

### Placeholder completions are blocking

`Onboarding::Readiness` treats any section whose `decision_metadata["placeholder"]` is
set as a blocking issue. That is what keeps the shell's stub completions from letting a
hotel submit. When you implement a section, its real save path must not set
`placeholder`, and you should confirm the readiness spec still fails for the sections
that remain stubs.

### Views

`app/views/hotel_portal/onboarding/`:

- `show.html.erb` renders `_progress_navigation`, header, then dispatches on section key
- `_actions.html.erb` / `_form_actions.html.erb` — Save draft / Save & continue / Skip
- one partial per section, named after the section key (`_property_profile.html.erb`, …)

`show.html.erb` currently guards the real-partial branch with an inline array of Phase 4
keys. Replace that with the same implemented-sections constant the controller uses so the
two cannot drift.

Follow `DESIGN.md`: PanelsUI components, semantic tokens, no native selects.

Repeating onboarding records use `HotelPortal::Setup::RecordTable`; do not build a
page-local `PanelsUI::Table` plus a separate mobile-card implementation. The component
currently owns inline draft rows for Staff and Taxes. When a later phase needs persisted
records or detail sheets, extend its semantic API while preserving those existing modes.
The shared component remains responsible for the leading `Remove` control, optional
trailing `Actions` control, add action, empty state, accessibility, and mobile reflow.
The Phase 6 Rooms spreadsheet uses its documented horizontal-scroll mode instead of mobile
reflow; Staff and Taxes retain the default stacked behavior.

### Navigation actions

`update` dispatches on `params[:navigation_action]`: `save_draft`, `save_continue`, `skip`.
`save_draft` marks `in_progress` and stays on the page. `save_continue` completes and
advances via `@navigation.next_entry`. `skip` is only valid for non-required sections and
must record an explicit decision, not silent omission.

### Read-only and changes-requested states

`update` returns `redirect_read_only` when the hotel is in `pending_review`. The presenter
exposes `read_only?` and `changes_requested_message`. Any new form partial must respect
`@presenter.read_only?` and render without editable controls in that state.

### Tests

Existing coverage to extend:

- `spec/services/onboarding/foundation_spec.rb` — catalog, navigation, readiness, lifecycle
- `spec/services/onboarding/property_and_team_spec.rb`, `taxes_and_room_revenue_spec.rb` —
  service specs per slice. Add a sibling named for the sections it covers, not for the
  delivery phase: the phase number is scheduling, and means nothing to a later reader.
- `spec/requests/hotel_portal/onboarding_spec.rb` — auth, navigation, save, skip, locking
- `spec/system/hotel_portal/onboarding_spec.rb` — critical owner path

Per `PLAN.md`, each slice needs service/model specs, request specs, view/component specs
for progress state, and system coverage of the owner path. Run the relevant domain plus
RuboCop; do not run the full CI suite per slice.

```bash
bin/test hotel_management
```

```bash
bin/rubocop
```

## Rules that apply to every phase

1. **Reuse domain services; do not fork their rules.** The onboarding domain orchestrates
   and presents; `RoomTypes`, `RatePlans`, `HotelOps`, `ExtraCharges`, `Discounts`,
   `PaymentMethods`, `ChannelManagers` remain the source of behaviour.
2. **No onboarding-only shadow records for domain data.** Rooms, rates, and inventory are
   the real records. The one sanctioned exception is queued invitations
   (`onboarding_staff_drafts`), because the existing invitation services send immediately.
3. **Do not initialize defaults as a page-visit side effect.** Several settings controllers
   call `EnsureDefaults` in a `before_action`. `PLAN.md` forbids that pattern in onboarding —
   provisioning must be a deliberate action.
4. **Invalidate downstream, warn rather than delete.** When an upstream change breaks a
   completed section, move it to `needs_attention` with an explanatory audit event.
   Do not silently delete referencing records.
5. **No portal redirect enforcement yet.** That is Phase 12. Do not add global redirects.
6. **Legacy status writes stay untouched.** Phase 13 removes them. If you touch a domain
   service that advances legacy `Hotel#status` (e.g. `SaveRoomType`), leave that behaviour
   alone unless your handoff says otherwise.
