# Typography

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
