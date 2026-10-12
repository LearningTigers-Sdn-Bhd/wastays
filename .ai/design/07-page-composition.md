# Page composition

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
