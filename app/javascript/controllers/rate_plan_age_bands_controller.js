import { Controller } from "@hotwired/stimulus"

// Repeatable "age band" rows for a per-person rate plan (min age, max age,
// price multiplier, label). Mirrors the INDEX-template pattern used by
// booking_room_rows_controller.js.
export default class extends Controller {
  static targets = ["rows", "row", "template", "addButton", "emptyState"]

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
    const row = event.currentTarget.closest("[data-rate-plan-age-bands-target~='row']")
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
