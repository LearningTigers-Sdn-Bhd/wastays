import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "empty"]

  add() {
    const index = `${Date.now()}-${this.rowTargets.length}`
    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))

    const row = this.rowTargets.at(-1)
    row?.querySelector("input, button")?.focus()
    this.#syncEmptyState()
  }

  remove(event) {
    event.currentTarget.closest("[data-onboarding-hotel-taxes-target='row']")?.remove()
    this.#syncEmptyState()
  }

  #syncEmptyState() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.rowTargets.length > 0
    }
  }
}
