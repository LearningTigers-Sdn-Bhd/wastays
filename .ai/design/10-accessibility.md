# Accessibility

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
