import { Controller } from "@hotwired/stimulus"

// Shows the pricing-value field when a derived pricing mode needs a value.
export default class extends Controller {
  static targets = ["value"]

  toggle(event) {
    this.valueTarget.classList.toggle("hidden", event.currentTarget.value === "same")
  }
}
