import { Controller } from "@hotwired/stimulus"

// Makes "Reason details" required only when the backdate reason is "Other".
// The reason select and details textarea are PanelsUI primitives that own their
// own markup, so we read them by field name rather than per-control targets.
export default class extends Controller {
  static targets = ["optionalBadge"]

  connect() {
    this.toggle()
  }

  get select() {
    return this.element.querySelector('[name="backdate_reason"]')
  }

  get details() {
    return this.element.querySelector('[name="retroactive_reason"]')
  }

  toggle() {
    const select = this.select
    const details = this.details
    if (!select || !details) return

    const isOther = select.value === "Other"
    details.required = isOther
    if (this.hasOptionalBadgeTarget) {
      this.optionalBadgeTarget.classList.toggle("hidden", isOther)
    }
  }
}
