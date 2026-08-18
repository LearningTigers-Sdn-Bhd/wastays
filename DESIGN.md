---
version: "1.1"
last_updated: 2026-08-17
---

# WAStays Portal UI Contract

This contract governs Admin, Hotel, Corporate, and Guest portal UI. Public and
marketing pages are outside its scope. Generated PDFs follow section 12, not the
screen rules above it.

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

These roles mirror the type tokens defined in `app/assets/tailwind/panel/*`.
When a case is ambiguous, resolve it against those tokens, not a nearby page.

## 4. Spacing

Use the established Tailwind spacing scale by role:

- Inline and icon gaps: `1`, `1.5`, `2`
- Control and component gaps: `2.5`, `3`, `4`
- Section spacing: `5`, `6`, `8`
- Exceptional workflow separation: `10`

Prefer `gap-*` and `space-y-*` for relationships and component density options
for internal padding. Do not use arbitrary spacing values or copy spacing from a
nearby page without confirming that the content relationship is the same.

This scale mirrors `app/assets/tailwind/panel/*`; resolve borderline choices
against those tokens.

Correct:

```erb
<%# section-level rhythm, then component-level gaps inside %>
<section class="space-y-6">
  <div class="flex items-center gap-2">
    <%= app_icon "calendar" %>
    <h2 class="text-base font-semibold">Bookings</h2>
  </div>
  <div class="grid gap-4 lg:grid-cols-2"><%# ... %></div>
</section>
```

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

Model new primitives on the shadcn Nova theme: a compact, small-scale UI with
tight density, restrained radii and shadows, and modest control sizing. Match
that character rather than introducing a larger or heavier look, and express it
through the `PanelsUI` tokens rather than hard-coded values.

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

Correct:

```erb
<%= render PanelsUI::FormField.new(
      form: form,
      attribute: :board,
      label: "Board basis",
      hint: "Keyboard: type to jump, arrows to move, Enter to pick.") do |field| %>
  <% field.with_select_menu(
       [
         { label: "Room only", value: "room_only" },
         { label: "Breakfast included", value: "bnb" },
         { label: "Full board", value: "full" }
       ],
       prompt: "Select a board basis") %>
<% end %>
```

## 7. Page composition

Components standardize controls and interaction behavior. They do not prescribe
one universal page layout.

Compose each page around the user's primary task, information hierarchy,
content volume, decision frequency, action risk, mobile behavior, and total
scroll cost.

- Prefer progressive disclosure, tabs, sheets, dialogs, collapsibles, or
  dedicated pages when they reduce scanning and scrolling.
- When adding tabs to a new or redesigned page, use `PanelsUI::Tabs` with the
  `line` variant. Use the `pill` variant only when it is explicitly requested.
- Do not reduce scroll by shrinking typography, controls, or spacing.
- Avoid unnecessary card nesting, repeated explanations, duplicated headings,
  unrelated workflows in one continuous form, and actions far from the content
  they affect.

A card is not the default container. Structure pages with labelled `<section>`
regions and heading hierarchy. Reach for `PanelsUI::Card` (or `MetricCard`) only
when the content genuinely needs a bounded, elevated surface — not to wrap every
section.

Plain labelled sections are the default and the priority. Cards are a
deliberate exception, justified only by the content, not by preference. A set of
distinct, self-contained offers meant to be compared — such as a
plan-comparison view — can warrant bounded surfaces, because the content is
inherently discrete. That justification comes from the content itself, not from
a nearby page that happens to use cards. When in doubt, default to a section.

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

## 9. Interaction ownership

- Use `PanelsUI` for shared UI behavior and presentation.
- Use Stimulus for application-specific behavior.
- Use Turbo for navigation, frames, and server-rendered updates.
- Do not introduce a second implementation of an existing interaction.
- Do not mix business behavior into a visual primitive.

## 10. Accessibility

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

## 11. Validation

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

## 12. Generated PDFs

Sections 1–11 govern screen UI only. Generated PDFs are print, not portal, and
follow this section instead. Nothing here licenses screen-side exceptions.

**Print uses its own faces, deliberately.** Screens use Inter. PDFs use
**Public Sans** for text and **Bricolage Grotesque** for report titles. Public
Sans was designed for dense administrative print and holds up at the 7–8pt sizes
report metadata needs; Bricolage separates the report title from the hotel name
by typeface rather than by size alone. This divergence from Inter is a decision,
not drift. Do not "correct" PDFs back to Inter.

Both faces are vendored in `app/assets/fonts` with their OFL licences. Do not
switch them to system fonts: a system font that lacks a bold sibling silently
renders every bold weight as regular, which is what these files exist to prevent.
Non-Latin text falls through to a system CJK font, and its absence is logged
rather than fatal.

Use `PdfTheme` tokens. Never a raw number:

- `TYPE`: `display` 20 (title, display face), `stat` 14 (stat strip values),
  `subhead` 12 (hotel name), `heading` 11 (section titles), `body` 9 (table cells),
  `small` 8 (table headers, address), `micro` 7 (metadata and stat labels, footer)
- `SPACE`: 4pt grid — `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 20
- `COLORS`, `RULE_WIDTH`, `PAGE_MARGIN`, `TABLE_CELL_PADDING`,
  `LABEL_TRACKING`
- `format_date` / `format_time` for every date and time

Unlike screen UI, uppercase and tracking are correct for print at `micro`: they
carry the metadata label tier, which cannot rely on size alone at 7pt. Prawn
cannot reach OpenType small caps.

Rules that exist because breaking them has already caused bugs:

- **Never `shrink_to_fit` scale-critical text.** It makes the same role render at
  different sizes on different reports. Let text wrap instead.
- **Dense tables step *down* the scale, never up.** Report services pass column
  widths tuned to their current size; widening text silently overflows and
  *drops content*. Horizontal cell padding stays at 6 for the same reason.
- **Prawn cannot apply OpenType features at render time.** Public Sans has
  `tnum` frozen into the vendored files so money columns align. Any feature you
  need must be baked in at vendor time, not requested in code.
- **prawn-table measures row heights when the table is built.** A size set via
  `row(n).style` afterwards is drawn but not measured, so the row gets sized for
  the document default. Set sizes at cell construction.
- **prawn-table applies `cell_style` after per-cell hashes.** A per-cell colour
  that `cell_style` also sets will be overridden. `PdfDataTable` therefore keeps
  only padding and `valign` in `cell_style`; size, borders and colour are set on
  every cell at construction, which is also what lets a caller hand one cell its
  own hash.
- **prawn-table cells reject `character_spacing`.** Tracked text must be drawn
  with measured text boxes.

A table that carries more columns than its page holds takes `density: :dense`
(`TABLE_TYPE`), which steps the whole table down one size. It does not tighten
its columns or shrink one cell — a table has two sizes and no others. A block
narrower than the measure takes `position: :right`, and its section title goes
with it.

Summary metrics are `PdfStatStrip` — label above value, columns divided by hairlines,
never filled. A tint behind short values reads as an empty table header, which is why
the metadata strip dropped its own fill. The strip fits its column count to the page
(four across needs landscape, portrait takes three) because the value size is fixed by
its role and must not shrink to fit. Reach for it through
`PdfReportBuilder#add_summary`, or directly in a document that draws its own body.

Facts about the document sit in one of three places, and never in two at once:

- `PdfReportFrame`'s **metadata strip** — one short value per label, on one line,
  bounded by rules. The default is period, generated, prepared by.
- `PdfDetailGrid` — the same label-above-value tier without the bounding rules,
  wrapping to as many rows as the pairs need. For a second band of facts under
  the one the frame already drew.
- `PdfPartyBlocks` — headed columns of free-running lines, separated by white
  space rather than rules. This is for the parties to a document: who it bills,
  who issued it, what it covers. A block holds a name and an address, so its
  columns end at different heights and a label-value grid cannot carry it.
  A document wearing party blocks passes `metadata: []` so the frame draws no
  strip above them.

`PdfNoticeBand` carries a status that has to arrive before the document's numbers
do — a void, a reconstruction. `:danger` and `:warning` variants.

Build reports with `PdfReportBuilder`, which owns the frame, tables, and page
furniture. Reach for `PdfReportFrame` directly only when a document draws its own
body, and call `stamp_page_furniture` once at the end so continuation pages get a
running head. A document whose title is an identifier passes `eyebrow:` to name
what it is; a document that is not period-based passes its own `metadata:` pairs.
The footer marks every document `Confidential` because most are internal; a
document that goes to the guest or the payer passes `confidential: false`. A
document that bills in the hotel's name passes `hotel_contact:`, which the
reports leave off.

## Source of truth

- `app/components/panels_ui/**`
- `app/assets/tailwind/panel/**`
- portal shell layouts
- `app/services/hotel_portal/reports/exports/**` and `app/assets/fonts/**` for
  generated PDFs

Historical design plans are not authoritative when they conflict with this file
or the current `PanelsUI` implementation.

When this contract and the `PanelsUI` implementation disagree, fix whichever is
wrong in the same PR. Do not leave the two in conflict.
