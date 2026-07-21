import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { focusId: String }

  connect() {
    if (!this.hasFocusIdValue || window.__stayViewOperationalFocusId !== this.focusIdValue) return

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        document.getElementById(this.focusIdValue)?.focus({ preventScroll: true })
        window.__stayViewOperationalFocusId = null
      })
    })
  }

  preserveFocus() {
    if (!this.hasFocusIdValue) return

    window.__stayViewOperationalFocusId = this.focusIdValue
    window.dispatchEvent(new CustomEvent("stay-view:preserve", { detail: { focusId: this.focusIdValue } }))
  }
}
