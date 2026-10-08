# Spacing

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
