# Booking Workspace Redesign Proposal

**Status:** Approved implementation scope
**Date:** 23 July 2026
**Target:** Hotel Portal booking workspace
**Primary objective:** Reduce visual and cognitive load while preserving the existing booking, folio, guest, billing, and operational workflows.

## Implementation Mandate

This proposal is an end-to-end workspace redesign specification. It is **not** a request to only remove cards, borders, radii, shadows, or background colors.

When instructed to implement this proposal, the implementation must complete all required work described in this document unless the user explicitly narrows the scope. The implementation is not complete after flattening the outer page shell.

The following are all required parts of the same redesign:

- Replace the repeated summary grid with the proposed single/group booking header.
- Reorganize the workspace information architecture and destination navigation.
- Introduce the standard and entity layout modes.
- Remove the permanent left rail from every standard-mode destination.
- Restrict the left rail to concrete folio selection on Folios.
- Restrict the left rail to concrete guest selection on Guests.
- Implement the specified single-booking and group-booking rail structures.
- Remove `All Folios`, `All Guests`, entity-selection dropdowns, and default-selection redirects.
- Resolve default folio and guest selection in the presenter.
- Handle group bookings with different child arrival and departure dates.
- Move confirmation tokens out of the primary header and into References.
- Redesign the information display within every workspace destination.
- Merge Source Details into Overview.
- Normalize typography according to `DESIGN.md`.
- Replace redesigned raw controls with appropriate PanelsUI components.
- Implement the specified empty, responsive, accessibility, Turbo, and focus behavior.
- Update and pass the relevant presenter, request, component, and system specs.

The only intentionally deferred part of this proposal is the optional migration from the existing `tab` query parameter to canonical path-based destination URLs. Deferring that route migration does not defer any visual, information-architecture, interaction, presenter, component, mobile, or testing requirement.

### Incomplete Implementations

The following do not satisfy this proposal:

- Removing card classes while leaving the existing hierarchy intact
- Changing spacing or typography without changing the repeated information structure
- Keeping the existing left rail on standard destinations
- Keeping the existing combined booking/context/entity rail
- Restyling the existing summary grid instead of replacing it
- Updating only Overview, Folios, or Guests while leaving the other destinations inconsistent
- Leaving native selects or one-off controls in redesigned workspace surfaces
- Stopping after the Foundation work package
- Treating later required work packages as optional follow-up ideas

## Summary

The booking workspace should become a flat, task-oriented page rather than a collection of bordered cards and information grids.

The redesign introduces two layout modes:

1. **Standard mode** — full-width content for Overview, Deposits, Billing, Room & Rate, Requests, and Audit Trail.
2. **Entity mode** — a narrow selection rail plus main content for Folios and Guests only.

The workspace remains one server-rendered Rails page controlled by `HotelPortal::Bookings::WorkspacesController#show`. Turbo continues to update the workspace without introducing separate index/detail controllers or a client-side application.

The implementation will preserve the existing URLs and workflow behavior while completing the full redesign. Canonical path-based workspace routes can be introduced afterward as a separate migration.

## Problems in the Current Workspace

The current design has several compounding issues:

- The booking summary and the workspace are enclosed in separate cards.
- Breadcrumbs, summary information, horizontal tabs, left-rail context, and panel headers repeat information.
- Booking number, guest, room, dates, and financial details appear in multiple places.
- Large information grids give every field equal visual weight.
- Borders are used as the primary grouping mechanism.
- Typography varies between panels and frequently uses very small, uppercase, tracked, bold, or black text.
- Actions appear inconsistently in the global header, panel header, table toolbar, rail, and sticky footer.
- All destinations show a left rail even when there is no meaningful entity to select.
- Folio and guest selection are mixed with booking context and workspace navigation.
- Native selection controls remain in parts of Deposits, Billing, and folio-related workflows.
- Empty states retain table or kanban structures that communicate little useful information.

## Design Principles

The redesign follows these rules:

- Flatten visual chrome, not information hierarchy.
- Use whitespace, headings, and restrained separators before cards.
- Show one page heading per destination.
- Keep global information in the global booking header.
- Keep child-booking information close to the selected child entity.
- Use tables only for comparison or transactional data.
- Use definition lists for labelled attributes.
- Use cards only for genuinely distinct, self-contained entities.
- Use PanelsUI components for controls and shared interaction behavior.
- Preserve URL state, Turbo navigation, keyboard operation, and browser history.
- Keep group and single-booking behavior structurally consistent.

## Information Architecture

The proposed workspace navigation is:

- Overview
- Folios
- Deposits
- Billing
- Guests
- Room & Rate
- Requests
- Audit Trail

`Source Details` should be merged into the Overview references section because it does not contain enough independent workflow content to justify a primary destination.

Navigation items remain real links. They may initially use the existing `tab` parameter, but they should behave as destination navigation rather than client-side content toggles.

## Layout Modes

### Standard Mode

Standard mode is used for:

- Overview
- Deposits
- Billing
- Room & Rate
- Requests
- Audit Trail

```text
Booking header
Workspace navigation
────────────────────────────────────────────

Page heading                              Actions

Full-width content
```

There is no permanent left rail in standard mode.

### Entity Mode

Entity mode is used only for:

- Folios
- Guests

```text
Booking header
Workspace navigation
────────────────────────────────────────────

┌──────────────────┬──────────────────────────────────────
│ Entity selector  │ Selected entity
│                  │
│ Folios or guests │ Full working content
│ only             │
└──────────────────┴──────────────────────────────────────
```

The entity rail has one responsibility: selecting a concrete folio or guest.

The rail must not contain:

- Workspace destination navigation
- An “All Folios” item
- An “All Guests” item
- Duplicate group summary information
- Forms or unrelated actions
- Multiple nested hierarchy levels

## Booking Header

The header contains only information that is stable and meaningful at the current booking scope.

### Single Booking

```text
←  Zakaria Iskandar                                      [IN HOUSE]
   Booking WS-10000043
   Room 105 · 22–25 Jul · 3 nights

                                         Outstanding balance    [ Actions ▾ ]
                                         MYR 1,220.40
```

### Group Booking

```text
←  Iskandar Family Group                    [GROUP] [PARTIALLY IN HOUSE]
   Group Booking WS-G000045
   2 bookings · 2 rooms · Stay dates vary

                                         Outstanding balance    [ Actions ▾ ]
                                         MYR 3,574.80
```

The group header must not present an artificial combined stay such as `22–28 Jul · 6 nights`.

If child bookings use different dates, the header shows `Stay dates vary`. Optional group-level date summaries must be explicitly labelled:

- Earliest arrival
- Latest departure

### References

The operational booking number is the primary reference used in:

- Header
- Breadcrumbs
- Entity-rail group headings
- Page context lines
- Operational links

The confirmation token is not a primary identifier. It belongs in the Overview references section:

```text
References

Booking number       WS-10000043
Confirmation code    JETUNE
Receipt number       WS-50000043
External reference   Not provided
```

The section should be named `References`, not `Identifiers`.

## Overview

### Single Booking Overview

The single-booking Overview contains:

- Stay
- Room and occupancy
- Financial summary
- References
- Special requests
- Internal notes

These should be plain labelled sections separated by spacing or `PanelsUI::Separator`.

### Group Booking Overview

The group Overview compares concrete child bookings:

```text
Bookings

Booking       Primary guest       Room       Arrival          Departure
────────────────────────────────────────────────────────────────────────
WS-10000043   Zakaria Iskandar    Room 105   22 Jul, 15:00   25 Jul, 12:00
WS-10000045   Nora Iskandar       Room 101   24 Jul, 15:00   28 Jul, 12:00
```

When dates differ, show one concise operational notice:

```text
Stay dates vary
Arrivals occur on 22 and 24 Jul. Departures occur on 25 and 28 Jul.
```

The notice must not imply that every child shares the earliest arrival or latest departure.

## Folio Entity Mode

### Single Booking Rail

```text
Folios                              + Add

● Guest Folio
  Open · MYR 0.00

  External Folio
  Company · MYR 1,220.40
```

### Group Booking Rail

```text
Folios                              + Add

Room 105 · WS-10000043
● Guest Folio
  Open · MYR 0.00

  External Folio
  Company · MYR 1,220.40

Room 101 · WS-10000045
  Guest Folio
  Open · MYR 2,354.40

  Company Folio
  Open · MYR 0.00
```

The rail uses one grouping level:

```text
Child booking / room
└── Folios
```

The selected folio content shows the exact child-booking context:

```text
Room 105 · Booking WS-10000043 · 22–25 Jul

Guest Folio
Open · Guest · MYR 0.00 outstanding
```

The folio ledger remains a table because users compare transactional rows. Upcoming charges remain a separate, quieter table section.

## Guest Entity Mode

### Single Booking Rail

```text
Guests                              + Add

● Zakaria Iskandar
  Primary guest

  Maya Iskandar
  Additional guest
```

### Group Booking Rail

```text
Guests                              + Add

Room 105 · WS-10000043
● Zakaria Iskandar
  Primary guest

  Maya Iskandar
  Additional guest

Room 101 · WS-10000045
  Nora Iskandar
  Primary guest
```

The selected guest content shows the exact child-booking context:

```text
Room 105 · Booking WS-10000043 · 22–25 Jul

Zakaria Iskandar
Primary guest
```

The guest form uses:

- `PanelsUI::FormField`
- `PanelsUI::FieldSet`
- `PanelsUI::FieldGroup`
- `PanelsUI::Input`
- `PanelsUI::SelectMenu`
- `PanelsUI::DatePicker`
- `PanelsUI::DateTimePicker`
- `PanelsUI::Button`

Save actions remain attached to the guest form. Unsaved-change protection must continue to work when changing the selected guest or leaving the destination.

## Entity Selection Behavior

The workspace remains one page. Missing entity parameters do not cause redirects.

Initial selection is resolved by the presenter:

- Folios select the primary folio, then the first available folio.
- Guests select the primary guest, then the first available guest.
- Group context resolves the first child booking by `group_position`, then applies the same entity preference.

When the user selects another entity:

- Turbo refreshes the workspace frame.
- The rail updates its selected state.
- The main pane renders the selected entity.
- The entity parameter is added to the URL for refresh and history support.

Initial URLs may remain:

```text
/workspace?tab=folio_operations
/workspace?tab=folio_operations&folio_id=123
/workspace?tab=guest_details
/workspace?tab=guest_details&booking_guest_id=456
```

No redirect is required when `folio_id` or `booking_guest_id` is absent.

The existing `redirect_group_entity_context!` behavior should be removed after equivalent presenter selection behavior is covered by tests.

## Mobile Behavior

Desktop entity mode uses a persistent rail.

On narrow screens:

- The main content remains full width.
- A labelled `Choose Folio` or `Choose Guest` button opens the same entity list in `PanelsUI::Sheet`.
- The sheet is not a dropdown.
- Selecting an entity closes the sheet, updates the Turbo frame, and moves focus to the selected content heading.
- The sheet preserves the same single/group grouping used by the desktop rail.

Standard-mode pages remain full width and do not show an entity-selection control.

## Content Display Rules

Use each display according to its task:

| Content | Display |
|---|---|
| Booking attributes | Definition list |
| Child bookings with different dates | Table |
| Folio ledger | Table |
| Upcoming charges | Compact table |
| Room nightly rates | Table |
| Billing parties | Restrained cards or entity rows |
| Deposits | Transaction table plus focused actions |
| Requests with active work | Kanban or status-grouped list |
| Empty requests | One actionable empty state |
| Audit history | `PanelsUI::Timeline` |
| Guest editing | Structured form sections |
| Confirmation and external codes | References definition list |

Avoid using grids solely to reduce vertical space.

## Typography

Typography follows `DESIGN.md`:

- Page title: `text-base font-semibold tracking-tight`
- Section title: `text-base font-semibold`
- Field label: `text-sm font-medium`
- Body and values: `text-sm`
- Supporting metadata: `text-xs`
- Secondary content: `text-muted-foreground`

Remove decorative uppercase text, excessive tracking, `font-bold`, `font-black`, and page-local type scales.

Dates, amounts, and comparable numeric columns should use tabular numerals.

## PanelsUI Adoption

The redesign should prefer existing PanelsUI components:

- `PanelsUI::PageHeader`
- `PanelsUI::Tabs` with the line variant, while destination navigation remains tab-shaped
- `PanelsUI::Button`
- `PanelsUI::ButtonGroup`
- `PanelsUI::DropdownMenu`
- `PanelsUI::Badge`
- `PanelsUI::Separator`
- `PanelsUI::Table`
- `PanelsUI::Timeline`
- `PanelsUI::Alert`
- `PanelsUI::AlertDialog`
- `PanelsUI::Sheet`
- `PanelsUI::Dialog`
- `PanelsUI::FormField`
- `PanelsUI::FieldSet`
- `PanelsUI::FieldGroup`
- `PanelsUI::SelectMenu`
- `PanelsUI::Combobox` only where searchable selection is genuinely necessary

Native `<select>`, `select_tag`, and `PanelsUI::NativeSelect` must be removed from redesigned workspace surfaces unless a documented platform fallback is required.

## Rails Architecture

The redesign does not require:

- Database migrations
- New models
- New business services
- Separate folio or guest page controllers
- A client-side application

The primary implementation remains:

```text
HotelPortal::Bookings::WorkspacesController#show
├── BookingPresenter
├── Folios::ShowPresenter
├── WorkspacePresenter
└── workspaces/show
    ├── booking header
    ├── workspace navigation
    └── workspace frame
        ├── standard layout
        └── entity layout
            ├── entity rail
            └── active panel
```

### Presenter Responsibilities

`WorkspacePresenter` should own:

- Current destination
- Standard or entity layout mode
- Single or group context
- Header identity and metadata
- Mixed-date group summary
- Entity grouping
- Default entity selection
- Selected entity context label
- Destination and entity paths

Views should not reproduce selection or group-resolution logic.

### Controller Responsibilities

`WorkspacesController` should remain thin:

- Authorize access
- Load the booking and required associations
- Build presenters
- Load destination-specific audit data
- Render the full page or Turbo-frame partial

## Routing Strategy

### Phase 1: Preserve Existing URLs

The visual and interaction redesign should ship without simultaneously rewriting the routing surface.

Benefits:

- Lower regression risk
- Fewer changes to action return paths
- Existing bookmarks continue to work
- Visual behavior can be reviewed independently

### Phase 2: Optional Canonical Paths

After the redesign is stable, destination paths may become:

```text
/workspace/overview
/workspace/folios?folio_id=123
/workspace/deposits
/workspace/billing
/workspace/guests?booking_guest_id=456
/workspace/room-and-rate
/workspace/requests
/workspace/audit-trail
```

This remains one controller and one workspace page. Legacy `tab` URLs should redirect to canonical paths only during this later migration.

## Required Implementation Plan

All four work packages below are in scope. They are separated to make implementation and review safer; they are not alternative scopes, optional enhancements, or independent definitions of completion.

### Work Package 1 — Foundation

Estimated AI-assisted duration: **1–1.5 days**

- Flatten booking summary and workspace card shells.
- Introduce the new booking header.
- Normalize workspace navigation.
- Add standard and entity layout modes.
- Remove the left rail from standard destinations.
- Normalize heading and typography roles.

### Work Package 2 — Overview, Folios, and Guests

Estimated AI-assisted duration: **1.5–2 days**

- Implement single and group Overview.
- Handle variable child check-in and checkout dates.
- Move confirmation token into References.
- Implement folio-only entity rail.
- Implement guest-only entity rail.
- Remove “All” entity concepts.
- Resolve default entities without redirects.
- Preserve guest form and unsaved-change behavior.

### Work Package 3 — Remaining Workspace Panels

Estimated AI-assisted duration: **1.5–2 days**

- Flatten Deposits.
- Flatten Billing.
- Normalize Room & Rate.
- Replace empty Requests kanban with an actionable empty state.
- Migrate Audit Trail to the established timeline pattern.
- Merge Source Details into Overview.
- Replace remaining native selection controls.

### Work Package 4 — Validation and Hardening

Estimated AI-assisted duration: **1–1.5 days**

- Desktop and mobile rendered QA.
- Light and dark theme verification.
- Keyboard and screen-reader checks.
- Turbo history and focus checks.
- Long group, long guest name, and large folio-list states.
- Request, presenter, component, and system test updates.
- RuboCop and relevant domain test runs.

### Total Estimate

Required core milestone:

- **2–3 focused days** for the new shell, Overview, Folios, and Guests.

Complete proposal implementation:

- **4–6 focused days** with AI assistance.
- Keep one additional day as contingency for billing and Turbo regressions.

Optional path-based route migration:

- **1–2 additional days** after the visual redesign is stable.

The required core milestone is a review point, not the completion point. Completion requires all four work packages.

## Testing Strategy

### Presenter Specs

Cover:

- Standard versus entity layout mode
- Single versus group header metadata
- Mixed versus shared group stay dates
- Primary and fallback folio selection
- Primary and fallback guest selection
- Entity grouping and order
- Selected entity state
- References labels
- Destination paths

### Request Specs

Cover:

- Full-page rendering
- Turbo-frame rendering
- Missing entity IDs without redirects
- Explicit folio and guest selection
- Cross-hotel entity isolation
- Group child selection
- Audit feature gating
- Legacy destination compatibility
- Action return paths

### System Specs

Cover:

- Switching folios in single and group bookings
- Switching guests in single and group bookings
- Browser back and forward behavior
- Guest unsaved-change protection
- Guest validation errors
- Folio actions targeting the selected child booking
- Mobile entity-selection sheet
- Keyboard navigation and focus movement
- Mixed child stay dates
- Empty folio, request, note, and audit states

## Acceptance Criteria

The redesign is complete only when all of the following are true:

- The workspace has no unnecessary outer card shell.
- The summary information is replaced by one concise booking header.
- Standard destinations render full width without a left rail.
- Only Folios and Guests use an entity rail.
- The entity rail contains concrete entities only.
- Group entities are grouped by child booking and room.
- No `All Folios` or `All Guests` state exists.
- Missing entity parameters render a deterministic default without redirecting.
- Variable child booking dates are not represented as one shared stay.
- Confirmation token is shown only as a secondary confirmation code.
- Folio and guest content show their exact child-booking context.
- Typography follows `DESIGN.md`.
- Redesigned controls use PanelsUI primitives.
- Native selects are removed from redesigned surfaces.
- Empty states provide a clear next action.
- Mobile layouts remain usable without a permanent side rail.
- Turbo navigation, browser history, and focus behavior remain correct.
- Relevant request, presenter, component, and system specs pass.

## Risks and Mitigations

### Folio and Guest Selection State

**Risk:** Removing redirects may expose assumptions that selected entity IDs are always present.

**Mitigation:** Centralize deterministic selection in `WorkspacePresenter` and add explicit presenter/request coverage before removing controller redirects.

### Group Action Targeting

**Risk:** An action may apply to the group or wrong child booking.

**Mitigation:** Every entity-mode action must receive the selected entity’s concrete booking, not only the workspace root booking.

### Guest Form State

**Risk:** Turbo selection may discard unsaved changes.

**Mitigation:** Preserve the current confirmation behavior and test entity switching, destination switching, browser navigation, and validation failures.

### Billing Controls

**Risk:** Replacing native selects may affect Stimulus-driven billing matrices.

**Mitigation:** Migrate billing controls in a dedicated pass and test parent/child routing dependencies before removing the existing controls.

### Large Groups

**Risk:** A long folio or guest rail may become difficult to scan.

**Mitigation:** Keep one hierarchy level, use restrained group headings, preserve independent rail scrolling on desktop, and validate realistic large-group fixtures. Add search only if observed group sizes require it.

## Non-Goals

This proposal does not include:

- Redesigning booking creation
- Rewriting booking lifecycle services
- Changing folio accounting behavior
- Changing guest data models
- Adding new group-level financial calculations
- Introducing a JavaScript SPA
- Replacing Turbo
- Performing the canonical path migration in the same initial redesign

These non-goals do not authorize reducing the required redesign to a cosmetic flattening pass.
