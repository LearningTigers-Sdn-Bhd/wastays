import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enabled", "amountInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.amountInputTarget.disabled = !this.enabledTarget.checked
  }
}
