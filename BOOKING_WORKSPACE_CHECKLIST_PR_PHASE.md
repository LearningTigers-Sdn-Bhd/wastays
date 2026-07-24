# Booking Workspace Redesign — PR Phase Checklist

**Branch:** `refactor/booking-manage-page`
**Baseline:** `main` at `c7e94d072`
**Snapshot date:** 23 July 2026
**Source of truth:** `BOOKING_WORKSPACE_PROPOSAL.md`

## Mandatory Implementation Instruction

This checklist tracks the complete booking-workspace redesign. It is not a cosmetic flattening checklist.

All required phases must be completed before the proposal is considered implemented. A phase may be reviewed or merged independently, but completing an early phase does not authorize stopping the implementation.

The only optional phase is the final canonical path migration. Everything else in this checklist is required unless the user explicitly changes the scope.

## Checklist Legend

- `[x]` — present in the current branch
- `[ ]` — required and not yet complete
- **Committed** — included in one of the current branch commits
- **Validation pending** — code is present, but the required tests or rendered verification have not been completed

Do not mark a behavior complete merely because a presenter method, CSS class, or partial exists. The behavior must be connected to the rendered workspace and covered proportionately by tests.

## Current Git Snapshot

- [x] Branch contains ten commits beyond `main`
  - `905e02b33` — rename booking control panel to booking workspace
  - `bcd65e2cb` — flatten workspace shell and add booking header
  - `789300eca` — complete workspace foundation
  - `962ed409d` — complete Overview and Folio workspace
  - `904730fd1` — complete guest workspace
  - `f0e92c364` — complete mobile entity selection
  - `0d04599ba` — delete unreachable workspace rail code (Phase 2.5)
  - `d0385253a` — use semantic tokens for tourism tax menu items (Phase 2.5)
  - `2f3abbda6` — rename `booking-control-tabs` to `booking-workspace-tabs` (Phase 2.5)
  - `90df06548` — omit empty parenthetical from payment descriptions (Phase 2.5)
- [x] Working tree is clean; all Phase 2 implementation is committed
- [x] `BOOKING_WORKSPACE_PROPOSAL.md` is tracked
- [x] This checklist is tracked
- [x] Relevant tests have been run against the current branch

## Phase 0 — Workspace Rename and Structural Baseline

**Status:** Committed

### Naming and File Organization

- [x] Rename booking control-panel controllers to booking workspaces
- [x] Rename the workspace presenter and namespace it under `HotelPortal::Bookings`
- [x] Rename workspace actions controller
- [x] Rename booking control-panel services
- [x] Move booking workspace views under `app/views/hotel_portal/bookings/workspaces`
- [x] Update route helper call sites
- [x] Update related controller, presenter, service, request, and system spec names

### Initial Shell

- [x] Remove the former summary-row partial
- [x] Add a dedicated booking-header partial
- [x] Add a dedicated header-actions partial
- [x] Remove the outer workspace card border, radius, and shadow
- [x] Allow `panel-page` to own page padding
- [x] Add standard/entity layout-mode vocabulary to the presenter

### Phase 0 Exit Gate

- [x] Workspace renders from the renamed paths
- [x] Existing booking-workspace routes remain functional
- [x] Initial flattened shell and booking header are committed

## Phase 1 — Required Workspace Foundation

**Status:** Complete

This phase completes the workspace shell and layout architecture. It is not complete merely because the outer cards were removed.

### Global Booking Header

- [x] Replace the six-cell summary grid with one compact header — **Committed**
- [x] Use PanelsUI badges for booking/group status — **Committed**
- [x] Show operational booking number instead of confirmation token in the header — **Committed**
- [x] Show room, stay dates, and night count for single bookings — **Committed**
- [x] Show booking count, room count, and `Stay dates vary` for mixed-date groups — **Committed**
- [x] Show earliest arrival and latest departure with explicit labels — **Committed**
- [x] Show outstanding balance and global Actions menu — **Committed**
- [x] Preserve group identity in the global header while viewing a concrete group folio
- [x] Preserve group identity in the global header while viewing a concrete group guest
- [x] Ensure group status accurately represents mixed child statuses
- [x] Replace the breadcrumb confirmation token with the operational booking/group number
- [x] Remove obsolete summary-related presenter methods after all call sites are migrated
- [x] Verify long guest names, long group names, missing rooms, and missing dates

### Destination Navigation

- [x] Navigation remains link-based and Turbo-compatible — **Committed**
- [x] Rename `Booking Details` to `Overview`
- [x] Rename `Folio Operations` to `Folios`
- [x] Rename `Billing Preferences` to `Billing`
- [x] Rename `Guest Details` to `Guests`
- [x] Rename `Audit Trails` to `Audit Trail`
- [x] Remove `Source Details` from primary destination navigation
- [x] Preserve Audit Trail feature gating
- [x] Verify navigation remains usable at narrow desktop widths
- [x] Verify active destination state is announced accessibly

### Standard and Entity Layout Modes

- [x] Presenter returns `standard` or `entity` from `layout_mode` — **Committed**
- [x] Change `show_left_rail?` so it is true only for Folios and Guests
- [x] Remove the booking-context rail from Overview
- [x] Remove the booking-context rail from Deposits
- [x] Remove the booking-context rail from Billing
- [x] Remove the booking-context rail from Room & Rate
- [x] Remove the booking-context rail from Requests
- [x] Remove the booking-context rail from Audit Trail
- [x] Remove the generic `Change Context` control from standard-mode mobile pages
- [x] Render every standard destination as full-width content
- [x] Keep the optional right action drawer compatible with both layout modes
- [x] Confirm Guest mode does not render the right action drawer

### Repetition and Heading Hierarchy

- [x] Render one `h1` for the workspace identity
- [x] Render one destination heading for the active workspace destination
- [x] Remove repeated booking/group name from destination content where the global header already provides it
- [x] Remove repeated booking number from destination headers unless it identifies a concrete child booking
- [x] Remove repeated stay-date messaging between global header, destination subtitle, and alerts
- [x] Normalize heading order and semantic section labels

### Phase 1 Exit Gate

- [x] Standard destinations are full width
- [x] Only Folios and Guests can show an entity rail
- [x] The global header is correct in single, group-overview, group-folio, and group-guest contexts
- [x] Navigation labels match the approved information architecture
- [x] No primary breadcrumb uses the confirmation token
- [x] Desktop and mobile shell screenshots have been reviewed

## Phase 2 — Overview, Folios, and Guests

**Status:** Committed

### Overview — Single Booking

- [x] Replace the old identifier/stay/financial matrix with plain sections — **Committed**
- [x] Add separate Stay section — **Committed**
- [x] Add separate Financial section — **Committed**
- [x] Rename Identifiers to References — **Committed**
- [x] Relabel confirmation token as `Confirmation code` — **Committed**
- [x] Preserve Special Requests as a separate section — **Committed**
- [x] Use PanelsUI Button for Edit Dates — **Committed**
- [x] Integrate source/channel details into References — **Committed**
- [x] Confirm Internal Notes follows the same flattened section rhythm — **Committed**
- [x] Confirm values use appropriate tabular numerals — **Committed**
- [x] Verify empty values and unusually long external references — **Committed**

### Overview — Group Booking

- [x] Add distinct arrival-date and departure-date helpers — **Committed**
- [x] Add mixed-date variation notice — **Committed**
- [x] Add presenter specs for sorted distinct dates — **Committed**
- [x] Add request coverage for mixed-date messaging — **Committed**
- [x] Rename group Identifiers to References — **Committed**
- [x] Show child bookings in a comparison table — **Committed**
- [x] Remove duplicate `Stay dates vary` messaging from the group panel — **Committed**
- [x] Show separate Arrival and Departure columns rather than one ambiguous Stay range — **Committed**
- [x] Do not repeat earliest/latest dates in the Overview if already sufficiently represented in the header and booking table — **Committed**
- [x] Avoid repeating the group name below the global group header — **Committed**
- [x] Use the established PanelsUI table pattern where its API supports this comparison — **Committed**
- [x] Verify matching-date groups do not show a variation notice — **Committed**
- [x] Verify partially missing dates do not raise an exception — **Committed**

### Folio Entity Rail — Single Booking

- [x] Show only concrete folios belonging to the current booking — **Committed**
- [x] Remove booking-context and Overview rows — **Committed**
- [x] Remove collapsible booking containers when there is only one booking — **Committed**
- [x] Show folio name, status/payer context, and balance with restrained hierarchy — **Committed**
- [x] Highlight the selected folio without a large decorative block — **Committed**
- [x] Keep `Add Folio` attached to the folio rail — **Committed**
- [x] Render a clear no-folios state with an Add Folio action — **Committed**

### Folio Entity Rail — Group Booking

- [x] Group concrete folios by child booking/room — **Committed**
- [x] Use exactly one hierarchy level: child booking/room → folios — **Committed** (heading is now room number + room type; see Phase 3)
- [x] Remove `All Folios` — **Committed**
- [x] Remove group-overview selection from the folio rail — **Committed**
- [x] Avoid repeating all room, guest, status, and booking metadata on every child row — **Committed**
- [x] Preserve deterministic child ordering by `group_position` — **Committed**
- [x] Preserve deterministic folio ordering — **Committed**
- [x] Ensure Add Folio targets the intended concrete child booking — **Committed**

### Selected Folio Content

- [x] Normalize initial folio typography and semantic colors — **Committed**
- [x] Show exact child context: room, operational booking number, and child stay dates — **Committed**
- [x] Do not label a concrete child folio with only the workspace root booking — **Committed**
- [x] Preserve Edit, Close, Reopen, Payment, Charge, Adjustment, and More Actions behavior — **Committed**
- [x] Ensure every folio action targets the selected folio’s concrete booking — **Committed**
- [x] Preserve ledger and upcoming-charge behavior — **Committed**
- [x] Preserve group-deposit provenance — **Committed**
- [ ] Confirm long ledger descriptions and large amounts remain readable

### Guest Entity Rail — Single Booking

- [x] Show only concrete booking guests — **Committed**
- [x] Remove booking-context and Overview rows — **Committed**
- [x] Remove collapsible booking containers when there is only one booking — **Committed**
- [x] Show guest name and Primary/Additional role — **Committed**
- [x] Highlight the selected guest with restrained navigation styling — **Committed**
- [x] Keep Add Guest attached to the guest rail — **Committed**

### Guest Entity Rail — Group Booking

- [x] Group concrete guests by child booking/room — **Committed**
- [x] Use exactly one hierarchy level: child booking/room → guests — **Committed** (heading is now room number + room type; see Phase 3)
- [x] Remove `All Guests` — **Committed**
- [x] Remove group-overview selection from the guest rail — **Committed**
- [x] Preserve deterministic child and guest ordering — **Committed**
- [x] Ensure Add Guest targets the intended concrete child booking — **Committed**

### Selected Guest Content

- [x] ~~Show exact child context: room, operational booking number, and child stay dates~~ — **Superseded in Phase 3.** The guest content header was removed; the rail now carries child context as room number plus room type. See *Guests — Rail and Content Header*.
- [x] Preserve primary/additional guest behavior — **Committed**
- [x] Preserve contact, identity, date-of-birth, and boat-transfer fields — **Committed**
- [x] Replace redesigned selection controls with PanelsUI SelectMenu or Combobox — **Committed**
- [x] Preserve GRC and print actions — **Committed**
- [x] Preserve Save Guest and alternate save scopes — **Committed**
- [x] Preserve validation rendering and focus behavior — **Committed**
- [x] Preserve unsaved-change protection while switching guests or destinations — **Committed**

### Default Entity Selection Without Redirect

- [x] Presenter selects a primary guest when no guest ID is supplied for a standalone booking — **Committed**
- [x] Presenter selects a folio when no folio ID is supplied for a standalone booking — **Committed**
- [x] Resolve the default group child in the presenter — **Committed**
- [x] Resolve the default group folio in the presenter — **Committed**
- [x] Resolve the default group guest in the presenter — **Committed**
- [x] Remove `redirect_group_entity_context!` from the controller — **Committed**
- [x] Render the default folio without redirecting — **Committed**
- [x] Render the default guest without redirecting — **Committed**
- [x] Preserve explicit `folio_id` selection in the URL — **Committed**
- [x] Preserve explicit `booking_guest_id` selection in the URL — **Committed**
- [x] Preserve Turbo history and browser back/forward behavior — **Committed**
- [x] Add request coverage proving missing entity IDs do not redirect — **Committed**
- [x] Add request coverage proving cross-hotel entity IDs are rejected or ignored safely — **Committed**

### Mobile Entity Selection

- [x] Replace generic `Change Context` wording with `Choose Folio` or `Choose Guest` — **Committed**
- [x] Use PanelsUI Sheet rather than a dropdown — **Committed**
- [x] Reuse the desktop entity grouping inside the sheet — **Committed**
- [x] Close the sheet after selection — **Committed**
- [x] Move focus to the selected entity heading after Turbo replacement — **Committed**
- [x] Preserve unsaved guest-form confirmation before changing guests — **Committed**
- [x] Verify long group entity lists remain operable — **Committed**

### Phase 2 Exit Gate

- [x] Single and group Overview match the approved information hierarchy — **Committed**
- [x] Folio rail contains concrete folios only — **Committed**
- [x] Guest rail contains concrete guests only — **Committed**
- [x] No `All Folios` or `All Guests` state exists — **Committed**
- [x] Group entity pages render without controller redirects — **Committed**
- [x] Selected entity actions target the correct child booking — **Committed**
- [ ] Desktop and mobile Folio/Guest flows have been visually verified

## Phase 2.5 — Dead Code Cleanup

**Status:** Committed

Phase 1 removed the booking-context rail from the six standard destinations, but only at the call site. The rail partials and their presenter methods stayed in the tree, unreachable. Cleared before Phase 3 because Phase 3 refactors exactly those destinations.

- [x] Delete the eleven unreachable rail partials — **Committed**
- [x] Delete the presenter methods that fed them — **Committed**
- [x] Delete presenter methods kept alive only by their own specs — **Committed**
- [x] Delete the cascade orphans exposed by the above — **Committed**
- [x] Make `show_left_rail?` derive from `left_rail_mode` so the two cannot disagree — **Committed**
- [x] Cover the rail invariant across every destination — **Committed**
- [x] Replace hardcoded `slate` colors in the folio actions menu — **Committed**
- [x] Rename the stale `booking-control-tabs` identifier — **Committed**
- [x] Omit the empty parenthetical from gateway payment descriptions — **Committed**

### Phase 2.5 Exit Gate

- [x] No workspace partial is unreachable from a live render path
- [x] No presenter method is reachable only from a spec
- [x] A standard destination cannot claim a rail it has no partial for
- [ ] Standard destinations verified rendering without a rail in a running app

## Phase 3 — Remaining Workspace Destinations and PanelsUI

**Status:** Started — entity rails and the Guests content header are done

### Guests — Rail and Content Header

Design review of the rendered Guests destination found the same identity printed
three times: global header, rail row, and content header — with the content
header's first field (`Full name`) restating it a fourth time. Front desk works
from room number and room type, not reservation numbers.

- [x] Unify the standalone and grouped rails into one partial per entity
- [x] Lead rail group headings with the room number, qualified by room type
- [x] Fall back to the reservation number when a child has no room assigned
- [x] Omit the room-type line when no room type is resolvable
- [x] Remove the rail's `Guests`/`Folios` header, which restated the active tab
- [x] Attach `+ Add guest` / `+ Add folio` to each group so it targets that child
- [x] Gate each group's add action on that child booking's own status
- [x] Remove the guest content header (context line, name, and role)
- [x] Give the guest panel a static accessible name and its own focus target
- [x] Label the mobile entity bar with the selected entity instead of `Guests`
- [x] Lay guest content in two columns and pair fields within each section
- [x] Replace the two boat-transfer pickers with one `DateTimePicker` range
- [x] Give all three guest FieldSets one rule and spacing rhythm
- [x] Reduce rail selection to dot plus fill, without the ring
- [x] Migrate the guest footer to PanelsUI (`DropdownMenu`, `Button`, `ButtonGroup`)
- [x] Replace the footer's hardcoded `text-amber-600` with a semantic token
- [x] Constrain the guest footer to the content column rather than the full width
- [ ] Guard `Make primary` against discarding unsaved guest edits
- [x] Migrate the discard alert to `PanelsUI::AlertDialog` with semantic tokens
- [ ] Sweep the remaining orphaned presenter methods once Phase 3 lands


### Deposits

- [ ] Flatten deposit content into labelled sections
- [ ] Keep deposit history in a comparison/transaction table
- [ ] Move Collect Deposit into a focused dialog or sheet
- [ ] Move Release Held Deposits into a focused dialog or sheet
- [ ] Replace native payment-method selects with PanelsUI controls
- [ ] Preserve group deposit allocation behavior
- [ ] Provide actionable no-deposits state
- [ ] Verify destructive and irreversible actions require appropriate confirmation

### Billing

- [ ] Flatten Billing layout and remove unnecessary card nesting
- [ ] Keep billing parties as genuinely distinct entity rows or restrained cards
- [ ] Replace native account-type selects
- [ ] Replace native corporate-account selects
- [ ] Replace native settlement-type selects
- [ ] Migrate billing-route matrix controls without breaking dependent Stimulus behavior
- [ ] Preserve add, edit, archive, group-scope, and routing workflows
- [ ] Keep actions attached to the billing entity they modify

### Room & Rate

- [ ] Normalize the page heading and child-booking context
- [ ] Keep nightly values in a comparison table
- [ ] Preserve Change Room and Change Rate actions
- [ ] Preserve rate-impact warning and confirmation behavior
- [ ] Verify mixed group dates render only applicable nightly rows
- [ ] Verify missing rates and unassigned rooms

### Requests

- [ ] Replace the three-column empty kanban with one actionable empty state
- [ ] Use kanban/status grouping only when requests exist
- [ ] Normalize request-card typography and status badges
- [ ] Preserve Complete and Resolve actions
- [ ] Preserve group child-booking context
- [ ] Verify long request content and mixed request types

### Audit Trail

- [ ] Migrate audit history to the established PanelsUI Timeline pattern
- [ ] Preserve filters and change disclosure
- [ ] Preserve feature gating
- [ ] Preserve group and concrete child context
- [ ] Verify long audit histories and expanded changes

### Source Details Consolidation

- [ ] Move source into Overview References
- [ ] Move external reference into Overview References
- [ ] Move channel-manager reference into Overview References
- [ ] Remove Source Details from destination navigation
- [ ] Preserve legacy `source_details` URL behavior until canonical routing migration
- [ ] Remove obsolete Source Details presenter and view code after compatibility is covered

### Typography and Shared Components

- [ ] Remove remaining workspace `font-black`
- [ ] Remove decorative uppercase and excessive tracking
- [ ] Normalize page, section, field, body, and metadata roles
- [ ] Replace page-local badges with `PanelsUI::Badge`
- [ ] Replace page-local buttons with `PanelsUI::Button` where supported
- [ ] Replace page-local menus with `PanelsUI::DropdownMenu` where supported
- [ ] Replace native selects on redesigned surfaces
- [ ] Use semantic theme tokens only
- [ ] Use tabular numerals for comparable dates, counts, and amounts
- [ ] Confirm no unnecessary outer cards or nested cards remain

### Phase 3 Exit Gate

- [ ] Every standard destination follows the flattened section model
- [ ] Every redesigned control uses an appropriate PanelsUI primitive
- [ ] Source Details has been consolidated into Overview
- [ ] Empty states explain the next available action
- [ ] No standard destination renders an entity rail

## Phase 4 — Validation and Hardening

**Status:** Early test additions only

### Presenter Specs

- [x] Distinct group arrival/departure dates — **Committed**
- [x] Mixed-date variation notice — **Committed**
- [x] Matching-date variation omission — **Committed**
- [x] Standalone primary guest fallback — **Committed**
- [x] Standalone folio fallback — **Committed**
- [x] Standard versus entity layout mode — **Committed**
- [x] Left rail visible only for Folios and Guests — **Committed**
- [x] Group header identity on concrete folio/guest views — **Committed**
- [x] Default group child selection — **Committed**
- [x] Default group folio selection — **Committed**
- [x] Default group guest selection — **Committed**
- [x] Entity grouping and order — **Committed**
- [x] Exact child context labels — **Committed**
- [ ] Source consolidation

### Request Specs

- [x] References label and confirmation-code demotion — **Committed**
- [x] Mixed group stay-date notice — **Committed**
- [x] Default group folio renders without redirect — **Committed**
- [x] Default group guest renders without redirect — **Committed**
- [x] Explicit entity IDs render the correct entity — **Committed**
- [x] Cross-hotel entity isolation — **Committed**
- [x] Standard pages omit the left rail — **Committed**
- [x] Entity pages render the correct rail — **Committed**
- [ ] Source Details compatibility
- [ ] Action return paths preserve selected context
- [ ] Turbo-frame responses include the required workspace structure

### System Specs

- [x] Switch folios in a single booking — **Committed**
- [x] Switch folios across group child bookings — **Committed**
- [x] Switch guests in a single booking — **Committed**
- [x] Switch guests across group child bookings — **Committed**
- [x] Preserve browser back and forward navigation — **Committed**
- [x] Preserve guest unsaved-change confirmation — **Committed**
- [x] Preserve validation errors after failed guest save — **Committed**
- [ ] Verify folio actions target the selected child
- [ ] Verify mobile entity-selection sheet
- [ ] Verify keyboard operation and focus movement
- [ ] Verify mixed child stay dates
- [ ] Verify relevant empty states

### Rendered Visual QA

- [x] Single booking Overview — desktop
- [ ] Group booking Overview with matching dates — desktop
- [ ] Group booking Overview with mixed dates — desktop
- [ ] Single booking Folios — desktop
- [ ] Group booking Folios — desktop
- [ ] Single booking Guests — desktop
- [ ] Group booking Guests — desktop
- [ ] Every remaining standard destination — desktop
- [ ] All required flows at mobile width
- [x] Light theme
- [ ] Dark theme
- [ ] Long names, references, amounts, and large groups
- [ ] Empty, validation, and destructive states

### Accessibility

- [x] One logical `h1` and hierarchical headings
- [ ] Every icon-only action has an accessible name
- [x] Every field has a visible label — **Committed**
- [ ] Visible focus is preserved
- [ ] Dialog and sheet focus is moved and restored
- [ ] Turbo updates provide appropriate focus or live-region feedback
- [x] Selection is not communicated by color alone — **Committed**
- [ ] Touch targets meet the project contract
- [ ] Reflow and zoom remain usable

### Test and Quality Commands

- [x] `git diff --check`
- [x] `bin/test spec/presenters/hotel_portal/bookings/workspace_presenter_spec.rb`
- [x] `bin/test spec/requests/hotel_portal/bookings/workspaces_spec.rb`
- [x] `bin/test spec/requests/hotel_portal/bookings/workspace_actions_spec.rb`
- [x] `bin/test spec/system/hotel/booking_workspace_navigation_spec.rb spec/system/hotel/booking_workspace_actions_spec.rb spec/system/hotel/booking_workspace_guest_editing_spec.rb spec/system/hotel/booking_workspace_mobile_spec.rb --serial` (split from the former `booking_workspace_phase6_spec.rb`)
- [x] `bin/test spec/system/hotel/folio_operations_ledger_spec.rb --serial`
- [ ] `bin/test spec/system/hotel/group_billing_routes_spec.rb --serial`
- [x] `bin/test bookings`
- [x] `bin/test financials`
- [x] `bin/rubocop`
- [ ] `bin/ci` before final merge

### Phase 4 Exit Gate

- [ ] Relevant tests pass
- [ ] Rendered desktop and mobile states have been inspected
- [ ] Accessibility requirements have been verified
- [ ] No unfinished compatibility comments remain
- [ ] No proposal acceptance criterion is outstanding

## Phase 5 — Optional Canonical Workspace Paths

**Status:** Explicitly deferred and not required for the initial redesign

- [ ] Introduce canonical destination paths
- [ ] Keep one workspace controller and one server-rendered page
- [ ] Migrate internal navigation and action return paths
- [ ] Redirect legacy `tab` URLs to canonical paths
- [ ] Preserve explicit folio and guest entity parameters
- [ ] Update affected request and system specs
- [ ] Remove the compatibility layer only after all callers are migrated

This optional phase must not be used as a reason to defer any requirement in Phases 1–4.

## Final Completion Gate

The booking workspace redesign is complete only when:

- [ ] Every required checkbox in Phases 1–4 is complete
- [ ] All acceptance criteria in `BOOKING_WORKSPACE_PROPOSAL.md` are satisfied
- [ ] The implementation has been visually reviewed in rendered desktop and mobile states
- [ ] Single and group booking flows are covered
- [ ] Folios and Guests are the only entity-rail destinations
- [ ] Group entity selection works without redirects
- [ ] Confirmation codes are secondary references, not primary identity
- [ ] Variable child dates are represented without implying one shared stay
- [ ] PanelsUI and typography requirements are satisfied
- [ ] Relevant tests and final quality commands pass
- [ ] The proposal and checklist accurately reflect the delivered implementation

Do not report the proposal as complete while any required checkbox above remains open.
