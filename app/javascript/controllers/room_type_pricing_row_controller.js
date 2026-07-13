import { Controller } from "@hotwired/stimulus"

// Scoped per room-type row in the rate plan form: shows the pricing value
// input only when this row's own mode select is set to a derived mode.
export default class extends Controller {
  static targets = [ "mode", "value" ]

  connect() {
    this.toggle()
  }

  toggle() {
    this.valueTarget.classList.toggle("hidden", this.modeTarget.value === "fixed")
  }
}
