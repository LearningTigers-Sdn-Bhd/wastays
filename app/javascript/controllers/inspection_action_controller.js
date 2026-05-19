import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notesCard", "notesInput"]

  open(event) {
    event.preventDefault()
    this.notesCardTarget.hidden = false
    requestAnimationFrame(() => this.notesInputTarget?.focus())
  }

  close(event) {
    if (event) event.preventDefault()
    this.notesCardTarget.hidden = true
  }
}
