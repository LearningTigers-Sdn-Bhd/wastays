# Hotel Onboarding Design Decisions

## Status

Agreed presentation and interaction decisions for hotel onboarding.

This document supplements the portal UI contract in `DESIGN.md`. Where they conflict, `DESIGN.md` remains authoritative.

## Experience principle

Onboarding is a focused temporary setup workspace, not the normal operational hotel portal.

Use:

- A dedicated onboarding layout
- A top navbar instead of the hotel portal sidebar
- Phase and step progress
- One responsibility per page
- Independent page-level saving and validation
- Consistent navigation and action placement

Do not implement onboarding as one long form, one oversized controller, or a query-parameter wizard.

## Layout

The onboarding layout contains:

1. A compact top navbar
2. High-level phase progress
3. Current phase substeps
4. One focused page body
5. A persistent but non-obscuring action area

```text
+------------------------------------------------------------------+
| WAStays   Property name                     Help  Owner  Sign out |
+------------------------------------------------------------------+
| Property - Team - Finance - Rooms & rates - Commercial - Review  |
+------------------------------------------------------------------+
| Phase name / current page                                        |
| Page title                                                       |
| Short task-specific guidance                                    |
|                                                                  |
| Current form or table                                            |
|                                                                  |
+------------------------------------------------------------------+
| Back                         Save draft        Save & continue    |
+------------------------------------------------------------------+
```

The navbar provides only the controls needed during setup:

- WAStays identity
- Current property identity
- Help or support
- Owner account menu
- Sign out

It does not expose normal hotel operations or the hotel portal sidebar.

## Information architecture

Thirteen pages are too many for a single horizontal stepper. Present six phases:

1. Property
2. Team
3. Finance
4. Rooms & rates
5. Commercial
6. Review

Show the pages within the active phase as local substeps.

Example:

```text
Property   Team   Finance   Rooms & rates   Commercial   Review
                    active

Finance
Taxes and fees -> Room revenue
```

On mobile, reduce this to clear text progress such as:

```text
Finance - Step 1 of 2
Taxes and fees
```

Use an accessible progress/details control when the complete journey needs to be inspected. Do not force all phases and pages into a horizontally compressed mobile control.

## Navigation states

Every step communicates both availability and progress:

- Complete: identifiable and clickable
- Current: clearly highlighted
- Available: clickable
- Locked: visible but disabled, with its prerequisite understandable
- Skipped: explicitly labelled
- Needs attention: warning label and explanation

Do not communicate state through colour alone.

### Backward movement

The owner may move backward to any available completed step.

### Forward movement

The owner moves forward after completing the current page or explicitly skipping an optional page. Locked future steps do not accept direct navigation.

### Direct URLs

- Completed previous page: open it.
- Current page: open it.
- Locked future page: redirect to the earliest unmet prerequisite and explain why.
- Onboarding root: redirect to the calculated resume page.

Browser history, refresh, and deep links must behave predictably.

## Page contract

Every onboarding page follows the same structure.

### Header

- Phase name
- Page title
- Short, task-specific description
- Required or optional label
- Page progress

### Main content

The page contains only the form or table for that responsibility. It does not include dashboard metrics, unrelated settings, promotional content, or multiple unrelated forms.

### Actions

Required page:

```text
Back | Save draft | Save & continue
```

Optional page:

```text
Back | Skip for now | Save & continue
```

Final page:

```text
Back | Save draft | Submit for review
```

Actions remain close to the form they submit. A sticky action area may be used on long pages if it does not obscure content, errors, or mobile controls.

## Saving and validation

### Save draft

- Saves valid partial work where the domain permits it.
- Keeps the owner on the same page.
- Does not mark the section complete.
- Provides clear saved feedback.

### Save & continue

- Runs page completion validation.
- Marks the section complete only when its completion contract passes.
- Navigates to the next available page.

### Back

- Does not silently submit incomplete data.
- Warns when unsaved changes would be lost.
- Returns to the previous available page.

For editable tables, rows may save individually, but the page still requires a clear confirmation action before it is considered complete.

## Forms versus tables

Use table-style editing only for repeatable structured records.

Good table candidates:

- Draft staff invitations
- Taxes and fees
- Room types
- Per-pax occupancy prices
- Extra charges
- Discounts
- Payment methods
- Corporate accounts

Use standard forms, detail pages, or contextual sheets for:

- Property profile
- Photos
- Amenities
- Detailed room information
- Child age-band setup
- Bulk rate and availability rules
- Channel manager connection and diagnostics

### Editable table pattern

```text
Actions | Name      | Type       | Amount | Tax
Remove  | Breakfast | Per person | 25.00  | SST
Remove  | Late out  | Fixed      | 50.00  | SST
        | + Add extra charge
```

The first column has an accessible name such as `Actions`; it is not visually or semantically empty. Every remove action includes the row's name in its accessible label.

Table requirements:

- Explicit add-row action
- Accessible remove-row action
- Inline field errors
- Unsaved-change feedback
- Keyboard operation
- Clear empty state
- Destructive confirmation where data dependencies exist
- Mobile reflow into stacked record editors instead of mandatory spreadsheet scrolling

Complex row details open in a sheet or dedicated editor instead of adding excessive columns.

## Per-pax pricing presentation

On desktop, the adult occupancy matrix may use:

- A sticky room-name column
- Horizontal scrolling
- Clear currency context
- Disabled unsupported occupancy cells
- Visible room maximum occupancy

Example:

```text
Room type       1 pax  2 pax  3 pax  4 pax  5 pax ... 12 pax
Room A (max 12)   RM     RM     RM     RM     RM         RM
Room B (max 4)    RM     RM     RM     RM      -          -
```

Unsupported cells:

- Display `—` or `Not available`
- Are not editable
- Are excluded from saving and validation
- Explain the reason through accessible text when necessary

On mobile, present one room at a time or group occupancy inputs into manageable rows. Do not require a twelve-column viewport.

Child age bands appear once in the rate-plan editor rather than being repeated for every room row.

## Optional sections

An optional section is not silently completed. It requires one of:

- Saved configuration
- An explicit `Skip for now` or equivalent decision

A skipped section remains visible in progress and in final review.

## Errors, warnings, and readiness

Use consistent meanings:

- Blocking issue: must be fixed before continuing or submitting
- Warning: owner may continue, but the consequence is explained
- Complete: completion contract passed
- Skipped: owner explicitly deferred an optional section
- Needs attention: earlier changes invalidated this section or admin requested changes

The review page groups findings by phase and links directly to the affected page.

Validation errors remain attached to their fields and are summarized at the page level. Focus moves to the error summary or first invalid field according to the portal accessibility contract.

## Responsive behaviour

Desktop:

- Full phase navigation
- Local substeps
- Table editors where suitable
- Sticky identity columns for wide pricing data

Mobile:

- Current phase and step count
- Compact progress details control
- Stacked record editors
- One room at a time for wide per-pax pricing
- Action area that remains reachable without covering content

## Accessibility

The onboarding experience must meet the portal's WCAG 2.2 AA requirement.

In particular:

- Logical heading order
- Labelled progress and step states
- Keyboard-operable navigation and editable tables
- Visible focus
- Field labels, hints, errors, and required state
- Status conveyed by text as well as icons and colour
- Appropriate focus movement after validation and navigation
- `aria-live` feedback for asynchronous row saves where needed
- Touch targets meeting the portal contract
- Reflow at zoom and narrow widths

## Visual implementation contract

Follow `DESIGN.md`:

- `panel-page` owns the content viewport.
- Use semantic portal tokens.
- Use existing `PanelsUI` components before adding primitives.
- Do not use native selects in portal UI.
- Keep headings and typography within the portal type scale.
- Prefer labelled sections over unnecessary card nesting.
- Use `app_icon` rather than inline SVG.

A new onboarding progress primitive is justified only if existing PanelsUI navigation components cannot express ordered progress, locked states, and responsive behaviour. Any new primitive requires a semantic API, accessibility, responsive behaviour, theme support, component specs, and real usage.

## Post-submission presentation

### Pending review

- Forms become read-only.
- Show submission status and submitted time.
- Show the complete setup summary.
- Explain that editing resumes only if admin requests changes.

### Changes requested

- Return the hotel to editable setup.
- Resume at the first affected section.
- Mark every requested section `Needs attention`.
- Display the admin's explanation in context.

### Live

- Normal hotel portal replaces onboarding as the default destination.
- Onboarding remains available as a read-only setup summary when useful.
- Future operational changes occur in regular hotel settings.
