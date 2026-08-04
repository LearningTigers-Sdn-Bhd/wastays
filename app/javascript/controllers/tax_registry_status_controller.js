import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["switch", "submit"]

  connect() {
    this.submitting = false
  }

  change() {
    if (this.submitting) return
    this.submitTarget.click()
  }

  start() {
    this.submitting = true
    this.switchTarget.disabled = true
    this.element.setAttribute("aria-busy", "true")
  }

  finish() {
    this.submitting = false
    this.switchTarget.disabled = false
    this.element.removeAttribute("aria-busy")
  }
}
