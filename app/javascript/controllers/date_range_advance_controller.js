import { Controller } from "@hotwired/stimulus"

// Focuses (and opens, where supported) the end-date picker as soon as a start
// date is chosen, so staff don't have to click into the next field manually.
export default class extends Controller {
  static targets = ["start", "end"]

  advance() {
    if (!this.hasStartTarget || !this.startTarget.value) return
    if (!this.hasEndTarget) return

    this.endTarget.focus()
    if (typeof this.endTarget.showPicker === "function") {
      try {
        this.endTarget.showPicker()
      } catch {
        // Some browsers throw if the picker can't be shown (e.g. not user-triggered); focus is still useful.
      }
    }
  }
}
