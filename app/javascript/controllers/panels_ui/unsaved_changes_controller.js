import { Controller } from "@hotwired/stimulus"
import { serializeForm } from "controllers/panels_ui/support/form_state"

// Identifier: panels-ui--unsaved-changes
//
// Attach to an element that wraps a PanelsUI::Sheet together with the forms
// inside it. The sheet asks permission before every dismissal — the ✕, a Cancel
// button, Escape, a click on the backdrop — and this controller holds the close
// back while there is progress worth keeping, then puts the question to the
// person in an alert dialog rather than throwing the work away silently.
//
// Progress is either a `form` target whose values differ from the ones it was
// rendered with, or a `step` target the person has opened and not finished (the
// "Return to service" question, say): a revealed step is a decision in flight,
// so it counts the same as typing.
export default class extends Controller {
  static targets = ["form", "step", "alert"]

  initialize() {
    // Set up here rather than in connect(): Stimulus may announce existing
    // targets before the controller's own connect() runs.
    this.pristine = new WeakMap()
    this.submitting = false
  }

  connect() {
    this.lifecycle = new AbortController()
    const signal = this.lifecycle.signal
    this.formTargets.forEach((form) => this.snapshot(form))
    // Controls inside the sheet (a date picker, a select menu) normalise their
    // own fields as they connect, so the values the person actually starts from
    // are the ones in place once the sheet is open, not the ones just rendered.
    this.element.addEventListener("panels-ui:sheet-open", () => this.formTargets.forEach((form) => this.snapshot(form)), { signal })
    this.element.addEventListener("panels-ui:sheet-close-request", (event) => this.onCloseRequest(event), { signal })
    // A submit is the person saving, so the close that follows is not a loss.
    this.element.addEventListener("submit", () => { this.submitting = true }, { capture: true, signal })
    this.element.addEventListener("turbo:submit-end", (event) => { this.submitting = event.detail?.success === true }, { signal })
  }

  disconnect() {
    this.lifecycle?.abort()
  }

  formTargetConnected(form) {
    this.snapshot(form)
  }

  onCloseRequest(event) {
    if (!this.unsaved) return

    event.preventDefault()
    this.sheet = event.target
    if (this.hasAlertTarget && !this.alertTarget.open) this.alertTarget.showModal()
  }

  keepEditing() {
    this.sheet = null
  }

  discardChanges() {
    const sheet = this.sheet
    this.sheet = null
    if (!sheet) return

    // The sheet only closes once it is the top overlay again, which it is not
    // until the alert has left the top layer.
    this.submitting = true
    const close = () => this.sheetControllerFor(sheet)?.dismiss()
    if (this.hasAlertTarget && this.alertTarget.open) {
      this.alertTarget.addEventListener("close", () => window.requestAnimationFrame(close), { once: true })
    } else {
      window.requestAnimationFrame(close)
    }
  }

  get unsaved() {
    if (this.submitting) return false
    if (this.stepTargets.some((step) => !step.hidden)) return true

    return this.formTargets.some((form) => serializeForm(form) !== this.pristine.get(form))
  }

  snapshot(form) {
    this.pristine.set(form, serializeForm(form))
  }

  sheetControllerFor(sheet) {
    return this.application.getControllerForElementAndIdentifier(sheet, "panels-ui--sheet")
  }
}
