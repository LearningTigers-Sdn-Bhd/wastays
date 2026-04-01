import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "slash"]

  connect() {
    this.hidePassword()
  }

  toggle() {
    if (this.inputTarget.type === "password") {
      this.showPassword()
    } else {
      this.hidePassword()
    }
  }

  showPassword() {
    this.inputTarget.type = "text"
    this.slashTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-label", "Hide password")
    this.buttonTarget.setAttribute("aria-pressed", "true")
  }

  hidePassword() {
    this.inputTarget.type = "password"
    this.slashTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-label", "Show password")
    this.buttonTarget.setAttribute("aria-pressed", "false")
  }
}
