import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["intermediaryToggle", "detailsSection", "detailsHiddenState"]

  connect() {
    this.toggleDetails()
  }

  toggleDetails() {
    const enabled = this.intermediaryToggleTarget.checked

    this.detailsSectionTarget.classList.toggle("hidden", !enabled)
    this.detailsHiddenStateTarget.classList.toggle("hidden", enabled)
  }
}
