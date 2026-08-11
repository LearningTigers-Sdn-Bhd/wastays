import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row"]

  add() {
    const index = `${Date.now()}-${this.rowTargets.length}`
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))

    const row = this.rowTargets.at(-1)
    row?.querySelector("input, button")?.focus()
  }

  remove(event) {
    event.currentTarget.closest("[data-onboarding-staff-drafts-target='row']")?.remove()
  }
}
