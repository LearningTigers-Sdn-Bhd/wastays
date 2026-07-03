import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { closeUrl: String, triggerSelector: String }

  connect() {
    this.handleClose = this.handleClose.bind(this)
    this.element.addEventListener("close", this.handleClose)
    this.element.showModal()
  }

  disconnect() {
    this.element.removeEventListener("close", this.handleClose)
  }

  close() {
    this.element.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  proceed() {
    this.element.close()
  }

  handleClose() {
    window.history.replaceState(window.history.state, "", this.closeUrlValue)
    document.querySelector(this.triggerSelectorValue)?.focus()
  }
}
