import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "details", "optionalBadge"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasSelectTarget || !this.hasDetailsTarget) return

    const selectEl = this.selectTarget
    const detailsEl = this.detailsTarget
    const isOther = selectEl.value === "Other"

    if (isOther) {
      detailsEl.required = true
      if (this.hasOptionalBadgeTarget) {
        this.optionalBadgeTarget.classList.add("hidden")
      }
    } else {
      detailsEl.required = false
      if (this.hasOptionalBadgeTarget) {
        this.optionalBadgeTarget.classList.remove("hidden")
      }
    }
  }
}
