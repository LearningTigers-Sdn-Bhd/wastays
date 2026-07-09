import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "icon"]

  toggle(event) {
    // Avoid triggering when clicking links or form controls inside the header
    if (event.target.closest("a, button, select, input")) {
      return
    }
    this.rowTargets.forEach(row => {
      row.classList.toggle("hidden")
    })
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("rotate-90")
    }
  }
}
