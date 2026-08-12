import { Controller } from "@hotwired/stimulus"

// Add and remove rows in an editable record table.
//
// The blank row lives in a <template> that sits after the last record, so it
// doubles as the insertion anchor — new rows go in immediately before it and
// land at the end of the list without the table body needing a target of its
// own. Its index placeholder is swapped for a fresh one on each add so the
// server sees a distinct set of params per row.
export default class extends Controller {
  static targets = ["template", "row", "empty"]

  add() {
    const index = `${Date.now()}-${this.rowTargets.length}`
    this.templateTarget.insertAdjacentHTML("beforebegin", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))
    this.#syncEmptyState()

    // Focus the first field, not the row's remove button — that sits ahead of
    // the fields in the markup and would hand focus straight to a destructive
    // control the operator never asked for.
    const row = this.rowTargets.at(-1)
    row?.querySelector("input:not([type='hidden']), select, textarea")?.focus()
  }

  async remove(event) {
    const row = event.currentTarget.closest("[data-record-table-target='row']")
    if (!row) return

    if (row.dataset.recordTablePersisted === "true") {
      const message = event.currentTarget.dataset.recordTableConfirm
      const confirmed = !message || await Turbo.config.forms.confirm(message, event.currentTarget)
      if (!confirmed) return

      const destroyInput = row.querySelector("input[data-record-table-destroy]")
      if (destroyInput) destroyInput.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }

    this.#syncEmptyState()
  }

  #syncEmptyState() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.rowTargets.some(row => !row.hidden)
    }
  }
}
