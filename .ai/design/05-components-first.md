# Components first

Before writing UI markup:

1. Search `PanelsUI` for an existing component.
2. Inspect its API and a relevant usage. Read its template, styles, behavior, and specs as needed for the change.
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
