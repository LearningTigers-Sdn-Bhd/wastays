import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notesPanel", "notesInput"]

  open(event) {
    if (event) event.preventDefault()
    this.notesPanelTarget.hidden = false
    requestAnimationFrame(() => this.notesInputTarget?.focus())
  }

  close(event) {
    if (event) event.preventDefault()
    this.notesPanelTarget.hidden = true
    if (this.hasNotesInputTarget) this.notesInputTarget.value = ""
  }
}
