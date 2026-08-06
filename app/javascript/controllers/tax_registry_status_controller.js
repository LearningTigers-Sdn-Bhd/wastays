import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["switch", "submit"]

  connect() {
    this.submitting = false
    // The rendered state is the saved state, and it is what a declined confirm
    // has to restore — the switch has already moved by the time the dialog opens.
    this.savedChecked = this.switchTarget.checked
  }

  change() {
    if (this.submitting) return
    this.submitTarget.click()
  }

  settled(event) {
    if (event.detail?.confirmed) return

    this.switchTarget.checked = this.savedChecked
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
