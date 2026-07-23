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

- `[x]` — present in the current branch or working tree
- `[ ]` — required and not yet complete
- **Committed** — included in one of the current branch commits
- **Working tree** — implemented but currently unstaged and uncommitted
- **Validation pending** — code is present, but the required tests or rendered verification have not been completed

Do not mark a behavior complete merely because a presenter method, CSS class, or partial exists. The behavior must be connected to the rendered workspace and covered proportionately by tests.

## Current Git Snapshot

- [x] Branch contains two commits beyond `main`
  - `905e02b33` — rename booking control panel to booking workspace
  - `bcd65e2cb` — flatten workspace shell and add booking header
- [x] No staged changes
- [x] Thirteen modified files in the working tree
- [x] `BOOKING_WORKSPACE_PROPOSAL.md` exists as an untracked file
- [x] Current unstaged diff passes `git diff --check`
- [ ] Current unstaged implementation changes are committed
- [ ] `BOOKING_WORKSPACE_PROPOSAL.md` is tracked
- [ ] This checklist is tracked
- [x] Relevant tests have been run against the current working tree

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

**Status:** Partially implemented in the working tree

### Overview — Single Booking

- [x] Replace the old identifier/stay/financial matrix with plain sections — **Working tree**
- [x] Add separate Stay section — **Working tree**
- [x] Add separate Financial section — **Working tree**
- [x] Rename Identifiers to References — **Working tree**
- [x] Relabel confirmation token as `Confirmation code` — **Working tree**
- [x] Preserve Special Requests as a separate section — **Working tree**
- [x] Use PanelsUI Button for Edit Dates — **Working tree**
- [ ] Integrate source/channel details into References
- [ ] Remove the independent Source Details destination and partial
- [ ] Confirm Internal Notes follows the same flattened section rhythm
- [ ] Confirm values use appropriate tabular numerals
- [ ] Verify empty values and unusually long external references

### Overview — Group Booking

- [x] Add distinct arrival-date and departure-date helpers — **Working tree**
- [x] Add mixed-date variation notice — **Working tree**
- [x] Add presenter specs for sorted distinct dates — **Working tree**
- [x] Add request coverage for mixed-date messaging — **Working tree**
- [x] Rename group Identifiers to References — **Working tree**
- [x] Show child bookings in a comparison table — **Working tree**
- [x] Remove duplicate `Stay dates vary` messaging from the group panel — **Working tree**
- [ ] Show separate Arrival and Departure columns rather than one ambiguous Stay range
- [ ] Do not repeat earliest/latest dates in the Overview if already sufficiently represented in the header and booking table
- [x] Avoid repeating the group name below the global group header — **Working tree**
- [ ] Use the established PanelsUI table pattern where its API supports this comparison
- [x] Verify matching-date groups do not show a variation notice — **Working tree**
- [x] Verify partially missing dates do not raise an exception — **Working tree**

### Folio Entity Rail — Single Booking

- [ ] Show only concrete folios belonging to the current booking
- [ ] Remove booking-context and Overview rows
- [ ] Remove collapsible booking containers when there is only one booking
- [ ] Show folio name, status/payer context, and balance with restrained hierarchy
- [ ] Highlight the selected folio without a large decorative block
- [ ] Keep `Add Folio` attached to the folio rail
- [ ] Render a clear no-folios state with an Add Folio action

### Folio Entity Rail — Group Booking

- [ ] Group concrete folios by child booking/room
- [ ] Use exactly one hierarchy level: child booking/room → folios
- [ ] Remove `All Folios`
- [ ] Remove group-overview selection from the folio rail
- [ ] Avoid repeating all room, guest, status, and booking metadata on every child row
- [ ] Preserve deterministic child ordering by `group_position`
- [ ] Preserve deterministic folio ordering
- [ ] Ensure Add Folio targets the intended concrete child booking

### Selected Folio Content

- [x] Normalize initial folio typography and semantic colors — **Working tree**
- [ ] Show exact child context: room, operational booking number, and child stay dates
- [ ] Do not label a concrete child folio with only the workspace root booking
- [ ] Preserve Edit, Close, Reopen, Payment, Charge, Adjustment, and More Actions behavior
- [ ] Ensure every folio action targets the selected folio’s concrete booking
- [ ] Preserve ledger and upcoming-charge behavior
- [ ] Preserve group-deposit provenance
- [ ] Confirm long ledger descriptions and large amounts remain readable

### Guest Entity Rail — Single Booking

- [ ] Show only concrete booking guests
- [ ] Remove booking-context and Overview rows
- [ ] Remove collapsible booking containers when there is only one booking
- [ ] Show guest name and Primary/Additional role
- [ ] Highlight the selected guest with restrained navigation styling
- [ ] Keep Add Guest attached to the guest rail

### Guest Entity Rail — Group Booking

- [ ] Group concrete guests by child booking/room
- [ ] Use exactly one hierarchy level: child booking/room → guests
- [ ] Remove `All Guests`
- [ ] Remove group-overview selection from the guest rail
- [ ] Preserve deterministic child and guest ordering
- [ ] Ensure Add Guest targets the intended concrete child booking

### Selected Guest Content

- [ ] Show exact child context: room, operational booking number, and child stay dates
- [ ] Preserve primary/additional guest behavior
- [ ] Preserve contact, identity, date-of-birth, and boat-transfer fields
- [ ] Replace redesigned selection controls with PanelsUI SelectMenu or Combobox
- [ ] Preserve GRC and print actions
- [ ] Preserve Save Guest and alternate save scopes
- [ ] Preserve validation rendering and focus behavior
- [ ] Preserve unsaved-change protection while switching guests or destinations

### Default Entity Selection Without Redirect

- [x] Presenter selects a primary guest when no guest ID is supplied for a standalone booking — **Working tree**
- [x] Presenter selects a folio when no folio ID is supplied for a standalone booking — **Working tree**
- [ ] Resolve the default group child in the presenter
- [ ] Resolve the default group folio in the presenter
- [ ] Resolve the default group guest in the presenter
- [ ] Remove `redirect_group_entity_context!` from the controller
- [ ] Render the default folio without redirecting
- [ ] Render the default guest without redirecting
- [ ] Preserve explicit `folio_id` selection in the URL
- [ ] Preserve explicit `booking_guest_id` selection in the URL
- [ ] Preserve Turbo history and browser back/forward behavior
- [ ] Add request coverage proving missing entity IDs do not redirect
- [ ] Add request coverage proving cross-hotel entity IDs are rejected or ignored safely

### Mobile Entity Selection

- [ ] Replace generic `Change Context` wording with `Choose Folio` or `Choose Guest`
- [ ] Use PanelsUI Sheet rather than a dropdown
- [ ] Reuse the desktop entity grouping inside the sheet
- [ ] Close the sheet after selection
- [ ] Move focus to the selected entity heading after Turbo replacement
- [ ] Preserve unsaved guest-form confirmation before changing guests
- [ ] Verify long group entity lists remain operable

### Phase 2 Exit Gate

- [ ] Single and group Overview match the approved information hierarchy
- [ ] Folio rail contains concrete folios only
- [ ] Guest rail contains concrete guests only
- [ ] No `All Folios` or `All Guests` state exists
- [ ] Group entity pages render without controller redirects
- [ ] Selected entity actions target the correct child booking
- [ ] Desktop and mobile Folio/Guest flows have been visually verified

## Phase 3 — Remaining Workspace Destinations and PanelsUI

**Status:** Not substantially started

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

- [x] Distinct group arrival/departure dates — **Working tree**
- [x] Mixed-date variation notice — **Working tree**
- [x] Matching-date variation omission — **Working tree**
- [x] Standalone primary guest fallback — **Working tree**
- [x] Standalone folio fallback — **Working tree**
- [x] Standard versus entity layout mode — **Working tree**
- [x] Left rail visible only for Folios and Guests — **Working tree**
- [x] Group header identity on concrete folio/guest views — **Working tree**
- [ ] Default group child selection
- [ ] Default group folio selection
- [ ] Default group guest selection
- [ ] Entity grouping and order
- [ ] Exact child context labels
- [ ] Source consolidation

### Request Specs

- [x] References label and confirmation-code demotion — **Working tree**
- [x] Mixed group stay-date notice — **Working tree**
- [ ] Default group folio renders without redirect
- [ ] Default group guest renders without redirect
- [ ] Explicit entity IDs render the correct entity
- [ ] Cross-hotel entity isolation
- [x] Standard pages omit the left rail — **Working tree**
- [x] Entity pages render the correct rail — **Working tree**
- [ ] Source Details compatibility
- [ ] Action return paths preserve selected context
- [ ] Turbo-frame responses include the required workspace structure

### System Specs

- [ ] Switch folios in a single booking
- [ ] Switch folios across group child bookings
- [ ] Switch guests in a single booking
- [ ] Switch guests across group child bookings
- [ ] Preserve browser back and forward navigation
- [ ] Preserve guest unsaved-change confirmation
- [ ] Preserve validation errors after failed guest save
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
- [ ] Every field has a visible label
- [ ] Visible focus is preserved
- [ ] Dialog and sheet focus is moved and restored
- [ ] Turbo updates provide appropriate focus or live-region feedback
- [ ] Selection is not communicated by color alone
- [ ] Touch targets meet the project contract
- [ ] Reflow and zoom remain usable

### Test and Quality Commands

- [x] `git diff --check`
- [x] `bin/test spec/presenters/hotel_portal/bookings/workspace_presenter_spec.rb`
- [x] `bin/test spec/requests/hotel_portal/bookings/workspaces_spec.rb`
- [x] `bin/test spec/requests/hotel_portal/bookings/workspace_actions_spec.rb`
- [x] `bin/test spec/system/hotel/booking_workspace_phase6_spec.rb --serial`
- [ ] `bin/test spec/system/hotel/folio_operations_ledger_spec.rb --serial`
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
