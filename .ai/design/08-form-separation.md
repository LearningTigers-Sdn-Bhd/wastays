# Form separation

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
