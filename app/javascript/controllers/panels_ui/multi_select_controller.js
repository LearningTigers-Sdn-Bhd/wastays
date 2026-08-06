import ComboboxController from "controllers/panels_ui/combobox_controller"

// A searchable multi-select. Everything — the class-strip, aria copying, form
// reset resync, Turbo-reconnect dedup, and empty-text override — is inherited
// from the combobox; the additions here are:
//   1. the Tom Select config (unlimited items + removable pills),
//   2. a compact trigger that shows up to maxVisibleItems pills then a "+N more"
//      badge, and
//   3. a selected-badges panel injected into the dropdown, below the search input,
//      where the full selection stays removable.
export default class extends ComboboxController {
  static values = {
    maxVisibleItems: { type: Number, default: 3 },
    allSelectedText: { type: String, default: "All options selected" }
  }

  tomSelectOptions() {
    return {
      ...super.tomSelectOptions(),
      // Unlimited selections, each rendered as a removable pill in the control.
      maxItems: null,
      // Keep the menu open after each pick so several can be chosen in a row.
      closeAfterSelect: false,
      // remove_button adds the per-item × affordance in the trigger.
      plugins: ["dropdown_input", "remove_button"]
    }
  }

  connect() {
    super.connect()
    this.buildSelectedPanel()
    this.buildAllSelectedMessage()
    // Tom Select fires change on every item add/remove (including the initial
    // preselection sync), which is exactly when the trigger + panel need redrawing.
    this.onSelectionChange = () => this.refreshSelection()
    // Typing narrows the option list; the all-selected message depends on both the
    // query and the remaining options, so recheck it on type and open too.
    this.onEmptyStateChange = () => this.updateEmptyState()
    this.control.on("change", this.onSelectionChange)
    this.control.on("type", this.onEmptyStateChange)
    this.control.on("dropdown_open", this.onEmptyStateChange)
    this.refreshSelection()
  }

  disconnect() {
    this.selectedPanel?.remove()
    this.selectedPanel = null
    this.allSelectedMessage?.remove()
    this.allSelectedMessage = null
    this.overflowBadge = null
    super.disconnect()
  }

  // getValue() returns an array of selected values; the native <select multiple>'s
  // `.value` only exposes the first. Compare the full selection sets instead so
  // echoed change events aren't mistaken for external divergence.
  valueMatchesNative() {
    const selected = this.control.getValue()
    const native = Array.from(this.nativeTarget.selectedOptions, (option) => option.value)
    return selected.length === native.length && selected.every((value) => native.includes(value))
  }

  refreshSelection() {
    this.updateTriggerOverflow()
    this.renderSelectedPanel()
    this.updateEmptyState()
  }

  // ─── "All options selected" message ─────────────────────────────────────────
  buildAllSelectedMessage() {
    this.allSelectedMessage = document.createElement("div")
    // Reuse the combobox empty styling; hidden until it applies.
    this.allSelectedMessage.className = "panel-combobox__empty panel-multi-select__all-selected is-hidden"
    this.allSelectedMessage.setAttribute("role", "status")
    this.allSelectedMessage.textContent = this.allSelectedTextValue
    this.control.dropdown.insertBefore(this.allSelectedMessage, this.control.dropdown_content)
  }

  // Show the message only when the menu has no options left *and* the user has not
  // typed a query (an unmatched query is Tom Select's own no_results case). Run
  // after Tom Select finishes re-rendering the option list.
  updateEmptyState() {
    if (!this.allSelectedMessage) return
    requestAnimationFrame(() => {
      if (!this.allSelectedMessage) return
      const query = (this.control.control_input?.value || "").trim()
      const remaining = this.control.dropdown_content.querySelectorAll(".option").length
      const allSelected = query === "" && remaining === 0 && this.control.getValue().length > 0
      this.allSelectedMessage.classList.toggle("is-hidden", !allSelected)
    })
  }

  // ─── Trigger: cap visible pills, collapse the rest into "+N more" ───────────
  updateTriggerOverflow() {
    const control = this.control?.control
    if (!control) return

    const items = Array.from(control.querySelectorAll(":scope > .item"))
    const max = this.maxVisibleItemsValue
    items.forEach((item, index) => item.classList.toggle("is-overflow", index >= max))

    const hidden = Math.max(0, items.length - max)
    this.overflowBadge?.remove()
    this.overflowBadge = null
    if (hidden === 0) return

    const badge = document.createElement("span")
    badge.className = "panel-multi-select__more"
    badge.textContent = `+${hidden} more`
    badge.setAttribute("aria-hidden", "true")
    // Append after the control's trailing input rather than between the pills.
    // Tom Select maps pills to the `items` array by their position among the
    // control's children — `insertAtCaret` inserts before `children[caretPos]`
    // (caret is always at items.length, i.e. before the input) and `removeItem`
    // splices at the pill's preceding-<div> count. A foreign node *between* pills
    // desyncs both, removing/inserting the wrong value; placed last it can't.
    control.appendChild(badge)
    this.overflowBadge = badge
  }

  // ─── Dropdown: full, removable selection below the search input ─────────────
  buildSelectedPanel() {
    this.selectedPanel = document.createElement("div")
    this.selectedPanel.className = "panel-multi-select__selected"
    // dropdown_content is the scrollable options list; put the panel above it so
    // it sits directly under the pinned search input.
    this.control.dropdown.insertBefore(this.selectedPanel, this.control.dropdown_content)
  }

  renderSelectedPanel() {
    if (!this.selectedPanel) return

    const values = this.control.getValue()
    this.selectedPanel.replaceChildren()
    this.selectedPanel.classList.toggle("is-empty", values.length === 0)
    if (values.length === 0) return

    const labelField = this.control.settings.labelField
    values.forEach((value) => {
      const option = this.control.options[value]
      const label = option ? option[labelField] : value

      const badge = document.createElement("span")
      badge.className = "panel-multi-select__badge"

      const text = document.createElement("span")
      text.className = "panel-multi-select__badge-label"
      text.textContent = label

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "panel-multi-select__badge-remove"
      remove.setAttribute("aria-label", `Remove ${label}`)
      remove.textContent = "×"
      remove.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.control.removeItem(value)
        this.control.refreshOptions(false)
      })

      badge.append(text, remove)
      this.selectedPanel.append(badge)
    })
  }
}
