import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.trigger = null
    this.discarding = false
    this.boundHandleClose = this.handleClose.bind(this)
    this.element.addEventListener("close", this.boundHandleClose)
  }

  disconnect() {
    this.element.removeEventListener("close", this.boundHandleClose)
  }

  open(event) {
    this.trigger = event.detail?.trigger || null
    this.discarding = false
    window.dispatchEvent(new CustomEvent("dropdown:close-all"))
    this.element.showModal()
  }

  keepEditing() {
    this.element.close()
  }

  discard() {
    const trigger = this.trigger
    this.discarding = true
    document.dispatchEvent(new CustomEvent("guest-details:discard-confirmed"))
    this.element.close()
    trigger?.click()
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.keepEditing()
  }

  handleClose() {
    if (!this.discarding) this.trigger?.focus()
    this.trigger = null
    this.discarding = false
  }
}
