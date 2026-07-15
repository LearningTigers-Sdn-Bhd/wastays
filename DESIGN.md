# WAStays Portal UI Contract

This contract governs Admin, Hotel, Corporate, and Guest portal UI. Public and
marketing pages are outside its scope.

## 1. Page ownership

`panel-page` owns the portal content viewport, including its width, height,
screen-edge padding, workspace behavior, and mobile-navigation clearance.

- Do not override, duplicate, cap, or compensate for `panel-page`.
- Do not add page-level `max-w-*`, replacement padding, negative margins, or
  arbitrary width and height values.
- Pages control only their internal layout.

## 2. Semantic styling

Use portal semantic tokens such as `background`, `foreground`, `card`,
`card-foreground`, `muted`, `muted-foreground`, `border`,
`border-interactive`, `primary`, and the semantic status tokens.

- Do not introduce palette utilities such as `slate-*`, `gray-*`, `indigo-*`,
  `red-*`, `green-*`, `white`, or arbitrary color values in portal UI.
- Use the established `PanelsUI` radius, border, shadow, and focus treatments.

## 3. Typography

- Page title: `text-base font-semibold tracking-tight`
- Section title: `text-base font-semibold`
- Card title: component default
- Field label: `text-sm font-medium`
- Body and descriptions: `text-sm`
- Supporting metadata: `text-xs`
- Secondary text: `text-muted-foreground`

Large operational values must use `PanelsUI::MetricCard` or another approved
data-display primitive.

Avoid decorative uppercase text, excessive tracking, `font-bold`, `font-black`,
and page-local type scales. Keep heading order semantic: `h1`, then `h2`, then
`h3`.

## 4. Spacing

Use the established Tailwind spacing scale by role:

- Inline and icon gaps: `1`, `1.5`, `2`
- Control and component gaps: `2.5`, `3`, `4`
- Section spacing: `5`, `6`, `8`
- Exceptional workflow separation: `10`

Prefer `gap-*` and `space-y-*` for relationships and component density options
for internal padding. Do not use arbitrary spacing values or copy spacing from a
nearby page without confirming that the content relationship is the same.

## 5. Components first

Before writing UI markup:

1. Search `PanelsUI` for an existing component.
2. Inspect its Ruby API, template, CSS, JavaScript, specs, and real usages.
3. Confirm whether its variants, slots, or density options meet the need.
4. Extend it when the requirement belongs to that component.
5. Introduce a primitive only when no existing primitive can own the pattern.

Do not create a new component merely because the desired appearance differs.
Do not duplicate an existing component with page-local Tailwind markup. Use
`app_icon`; do not add inline SVG icons.

A new primitive must include:

- a semantic API
- light and dark theme behavior
- keyboard and screen-reader behavior
- responsive behavior
- component specs
- at least one real usage

## 6. Selection controls

Do not use native `<select>`, Rails `f.select`, `select_tag`, or
`PanelsUI::NativeSelect` in portal UI.

- Use `PanelsUI::SelectMenu` for a finite option set.
- Use `PanelsUI::Combobox` when options require search or filtering.
- Use `PanelsUI::MultiSelect` when multiple values may be selected.
- Preserve labels, hints, errors, disabled state, keyboard navigation, and
  selected values through `PanelsUI::FormField`.

A native select is allowed only when explicitly required as a documented
accessibility or platform fallback.

## 7. Page composition

Components standardize controls and interaction behavior. They do not prescribe
one universal page layout.

Compose each page around the user's primary task, information hierarchy,
content volume, decision frequency, action risk, mobile behavior, and total
scroll cost.

- Prefer progressive disclosure, tabs, sheets, dialogs, collapsibles, or
  dedicated pages when they reduce scanning and scrolling.
- Do not reduce scroll by shrinking typography, controls, or spacing.
- Avoid unnecessary card nesting, repeated explanations, duplicated headings,
  unrelated workflows in one continuous form, and actions far from the content
  they affect.

### Planning and research preview

When planning or researching a UI creation or redesign, show the user a compact
ASCII layout preview before implementation if the user has not supplied a
design.

- Show the proposed information hierarchy and primary actions.
- Include desktop and mobile differences when they materially differ.
- Use the preview to expose layout and scroll decisions, not visual decoration.
- Do not require an ASCII preview for a user-supplied design, a small component
  change, or a narrowly scoped visual or behavioral fix.

## 8. Form separation

A page has one clear responsibility.

- Do not embed create or edit forms inside an index, table, dashboard, or
  unrelated detail page.
- Use a dedicated `new` or `edit` page, a dialog for a short focused decision,
  or a sheet for contextual editing that benefits from keeping the source
  visible.
- A settings page may itself be a form when updating those settings is its
  primary responsibility.
- Do not place unrelated forms on one page. Split them into routes, tabs,
  dialogs, or sheets.
- Keep submission actions attached to the form they submit.

## 9. Settings UI

Preserve the centralized settings groups, permissions, routes, tabs, active
states, and breadcrumbs. A visual redesign must not silently change information
architecture.

General Settings and Property Settings demonstrate valid component usage only.
They are not mandatory page-layout templates.

Within the General settings group:

- General is a valid component-usage reference.
- Notifications may be referenced after validating its components.
- Plan & Billing must be evaluated independently.
- Rate Settings is legacy and must not be used as a design, layout, spacing,
  typography, or component reference.

Rate Settings has not completed its `PanelsUI` migration. Treat its existing
markup as migration input, not accepted design-system precedent.

Before using any nearby page as precedent, confirm that it uses semantic panel
tokens, current validated `PanelsUI` components, styled selection components,
and this typography and spacing contract. Proximity does not make a page
authoritative.

## 10. Interaction ownership

- Use `PanelsUI` for shared UI behavior and presentation.
- Use Stimulus for application-specific behavior.
- Use Turbo for navigation, frames, and server-rendered updates.
- Do not introduce a second implementation of an existing interaction.
- Do not mix business behavior into a visual primitive.

## 11. Accessibility

All portal UI must meet WCAG 2.2 AA.

- Use semantic HTML before ARIA; do not recreate native semantics unnecessarily.
- Give every control an accessible name and complete keyboard operation.
- Preserve logical heading, DOM, focus, and reading order with visible focus.
- Meet AA contrast: 4.5:1 for normal text and 3:1 for large text and UI
  boundaries.
- Do not communicate meaning through color, icons, position, or motion alone.
- Associate fields with labels, hints, errors, required state, and disabled state.
- Move and restore focus correctly for dialogs, sheets, menus, and validation
  errors.
- Provide `aria-live` feedback for asynchronous status changes when necessary.
- Make pointer targets at least 24 by 24 CSS pixels; prefer 44 by 44 for primary
  touch controls.
- Support zoom, text resizing, reflow, reduced motion, and mobile keyboard use.
- Hide decorative icons from assistive technology.
- Validate keyboard use and accessible names on the rendered UI.

## 12. Validation

Before completing UI work, verify:

- existing components were inspected before extension or replacement
- semantic tokens and styled selection components are used
- `panel-page` ownership remains intact
- typography and heading hierarchy
- keyboard navigation and visible focus
- labels, hints, errors, disabled states, and long-content states
- mobile and desktop layouts
- light and dark portal themes where applicable
- empty, loading, error, and destructive states
- Turbo and Stimulus behavior
- relevant component and system specs

For meaningful visual changes, inspect the rendered page rather than source code
alone.

## Source of truth

- `app/components/panels_ui/**`
- `app/assets/tailwind/panel/**`
- portal shell layouts
- `app/helpers/hotel_portal/settings_navigation_helper.rb`

Historical design plans are not authoritative when they conflict with this file
or the current `PanelsUI` implementation.
