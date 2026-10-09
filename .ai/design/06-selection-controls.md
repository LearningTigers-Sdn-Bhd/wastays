# Selection controls

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
