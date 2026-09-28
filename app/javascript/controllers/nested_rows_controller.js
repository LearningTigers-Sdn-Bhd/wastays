import { Controller } from "@hotwired/stimulus"

// Repeatable nested-attribute rows: "Add" clones the template (NEW_RECORD is
// replaced with a unique index), "Remove" marks a saved row for destruction or
// drops an unsaved one.
export default class extends Controller {
  static targets = ["rows", "row", "template", "emptyState"]

  connect() {
    this.nextIndex = Date.now()
  }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", this.nextIndex++)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.syncEmptyState()
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-nested-rows-target~='row']")
    const destroyField = row.querySelector("[data-role='destroy']")

    if (destroyField) {
      destroyField.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }

    this.syncEmptyState()
  }

  syncEmptyState() {
    if (!this.hasEmptyStateTarget) return

    const hasVisibleRows = this.rowTargets.some((row) => !row.classList.contains("hidden"))
    this.emptyStateTarget.classList.toggle("hidden", hasVisibleRows)
  }
}
