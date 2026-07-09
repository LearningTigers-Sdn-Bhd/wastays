import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "trigger"]

  open() {
    this.dialogTarget.showModal()
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  dialogTargetDisconnected() {
    this.triggerTarget?.setAttribute("aria-expanded", "false")
  }

  connect() {
    this.handleClose = () => {
      this.triggerTarget.setAttribute("aria-expanded", "false")
      this.triggerTarget.focus()
    }
    this.dialogTarget.addEventListener("close", this.handleClose)
  }

  disconnect() {
    this.dialogTarget.removeEventListener("close", this.handleClose)
  }
}
