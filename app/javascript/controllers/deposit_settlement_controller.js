import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "reason", "details" ]
  static values = { miscellaneousCodeId: String }

  connect() {
    this.updateReason()
  }

  updateReason() {
    if (!this.hasDetailsTarget || !this.hasReasonTarget) return

    const miscellaneous = this.reasonTarget.value === this.miscellaneousCodeIdValue
    this.detailsTarget.classList.toggle("hidden", !miscellaneous)
    this.detailsTarget.querySelectorAll("input, textarea").forEach((field) => {
      field.required = miscellaneous
    })
  }
}
