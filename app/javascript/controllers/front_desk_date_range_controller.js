import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker", "start", "end"]

  connect() {
    this.form = this.element.closest("form")
    this.prepareSubmit = this.prepareSubmit.bind(this)
    this.form?.addEventListener("submit", this.prepareSubmit, true)
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.prepareSubmit, true)
    clearTimeout(this.enableTimer)
    this.enableTimer = null
  }

  rangeChanged() {
    if (!this.syncCompleteRange()) return

    const autoSubmit = this.application.getControllerForElementAndIdentifier(this.form, "auto-submit")
    autoSubmit ? autoSubmit.submitNow() : this.form?.requestSubmit()
  }

  prepareSubmit() {
    this.syncCompleteRange()
    const rangeInput = this.rangeInput
    rangeInput.disabled = true
    clearTimeout(this.enableTimer)
    this.enableTimer = setTimeout(() => {
      rangeInput.disabled = false
      this.enableTimer = null
    }, 0)
  }

  syncCompleteRange() {
    const [start, end] = this.rangeInput.value.split("/")
    if (!start || !end) return false

    this.startTarget.value = start
    this.endTarget.value = end
    return true
  }

  get rangeInput() {
    return this.pickerTarget.querySelector("[data-panels-ui--date-picker-target='input']")
  }
}
