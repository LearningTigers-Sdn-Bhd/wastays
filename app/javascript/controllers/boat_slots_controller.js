import { Controller } from "@hotwired/stimulus"

// The Add slot button lives in the section header; the blank slot card it
// reveals is rendered up front and kept hidden, so adding one costs no round
// trip and the new row looks exactly like the saved ones.
export default class extends Controller {
  static targets = ["card", "trigger", "time"]

  add() {
    this.cardTarget.hidden = false
    this.triggerTarget.hidden = true
    this.timeTarget.querySelector("button, input")?.focus()
  }

  cancel() {
    this.cardTarget.hidden = true
    this.triggerTarget.hidden = false
    this.triggerTarget.focus()
  }
}
