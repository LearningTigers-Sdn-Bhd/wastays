import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) {
        this.close()
      }
    }

    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.panelTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }
  }

  close() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.add("hidden")
    }
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }
}
