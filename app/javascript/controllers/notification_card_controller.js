import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "content"]

  connect() {
    this.refresh()
  }

  refresh() {
    const isEnabled = this.toggleTarget.checked
    this.element.classList.toggle("is-disabled", !isEnabled)
    this.element.dataset.disabled = (!isEnabled).toString()

    const inputs = this.contentTarget.querySelectorAll("input, select, textarea, button")
    inputs.forEach(input => {
      if (input.type !== "hidden") {
        input.disabled = !isEnabled
      }
    })
  }
}
