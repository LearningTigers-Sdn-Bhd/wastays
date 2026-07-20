import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "input"]

  toggle() {
    if (this.buttonTarget.disabled) return

    const pressed = this.buttonTarget.getAttribute("aria-pressed") !== "true"
    this.buttonTarget.setAttribute("aria-pressed", pressed.toString())
    this.buttonTarget.dataset.state = pressed ? "on" : "off"

    if (this.hasInputTarget) {
      this.inputTarget.value = pressed ? this.inputTarget.dataset.pressedValue : this.inputTarget.dataset.unpressedValue
      this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    this.dispatch("change", {
      detail: {
        pressed,
        value: this.hasInputTarget ? this.inputTarget.value : null,
        input: this.hasInputTarget ? this.inputTarget : null
      }
    })
  }
}
