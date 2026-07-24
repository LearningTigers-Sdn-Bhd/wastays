import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.buttonTarget.classList.toggle("hidden", this.inputTarget.value.trim() === "")
  }
}
