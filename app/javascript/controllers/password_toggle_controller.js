import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "slash", "showIcon", "hideIcon"]

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
    if (this.hasSlashTarget) this.slashTarget.classList.remove("hidden")
    if (this.hasShowIconTarget) this.showIconTarget.classList.add("hidden")
    if (this.hasHideIconTarget) this.hideIconTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-label", "Hide password")
    this.buttonTarget.setAttribute("aria-pressed", "true")
  }

  hidePassword() {
    this.inputTarget.type = "password"
    if (this.hasSlashTarget) this.slashTarget.classList.add("hidden")
    if (this.hasShowIconTarget) this.showIconTarget.classList.remove("hidden")
    if (this.hasHideIconTarget) this.hideIconTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-label", "Show password")
    this.buttonTarget.setAttribute("aria-pressed", "false")
  }
}
