import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  show(event) {
    event.preventDefault()

    if (!this.hasPanelTarget) return

    this.panelTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hide(event) {
    if (event) event.preventDefault()

    if (!this.hasPanelTarget) return

    this.panelTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  stop(event) {
    event.stopPropagation()
  }
}
