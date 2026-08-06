import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]

  toggle() {
    if (this.panelTarget.open) {
      this.close()
    } else {
      this.panelTarget.showModal()
      this.triggerTarget.setAttribute("aria-expanded", "true")
      this.panelTarget.querySelector("input")?.focus()
    }
  }

  close(event) {
    if (event?.type === "cancel") event.preventDefault()
    if (this.panelTarget.open) this.panelTarget.close()
  }

  closed() {
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.focus()
  }

  closeAfterSubmit() {
    if (this.panelTarget.open) this.close()
  }

  submit(event) {
    event.currentTarget.closest("form")?.requestSubmit()
  }
}
