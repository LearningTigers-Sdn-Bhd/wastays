import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "amountContainer"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (this.hasAmountContainerTarget) {
      if (this.checkboxTarget.checked) {
        this.amountContainerTarget.classList.remove("hidden")
      } else {
        this.amountContainerTarget.classList.add("hidden")
      }
    }
  }
}
