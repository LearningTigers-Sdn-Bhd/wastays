import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  show(event) {
    if (!this.hasOutputTarget) return

    const value = event.detail.value
    this.outputTarget.textContent = `Current value: ${Array.isArray(value) ? value.join(", ") || "none" : value ?? "none"}`
  }
}
