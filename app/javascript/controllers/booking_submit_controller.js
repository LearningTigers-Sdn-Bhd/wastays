import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  start() {
    if (!this.hasButtonTarget) return

    this.originalText = this.buttonTarget.textContent
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Creating booking..."
  }

  end() {
    if (!this.hasButtonTarget) return

    this.buttonTarget.disabled = false
    this.buttonTarget.textContent = this.originalText || "Confirm & Create Booking"
  }
}
