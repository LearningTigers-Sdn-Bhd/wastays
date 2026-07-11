import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.dirty = false
    this.submitting = false
    this.boundDocumentClick = this.documentClick.bind(this)
    this.boundDiscardConfirmed = this.discardConfirmed.bind(this)
    document.addEventListener("click", this.boundDocumentClick, true)
    document.addEventListener("guest-details:discard-confirmed", this.boundDiscardConfirmed)
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick, true)
    document.removeEventListener("guest-details:discard-confirmed", this.boundDiscardConfirmed)
  }

  markDirty() {
    this.dirty = true
  }

  submit() {
    this.submitting = true
    this.dirty = false
  }

  discardConfirmed() {
    this.dirty = false
  }

  documentClick(event) {
    if (!this.dirty || this.submitting) return

    const link = event.target.closest("a[href]")
    if (!link) return

    event.preventDefault()
    event.stopImmediatePropagation()
    document.dispatchEvent(new CustomEvent("guest-details:confirm-discard", {
      detail: { trigger: link }
    }))
  }
}
