import { Controller } from "@hotwired/stimulus"

// Identifier: stay-view--room-block-return
//
// Two steps for ending a room block: press "Return to service", then say what
// the room is worth. Keeping the second question out of the footer until it is
// asked stops it reading as two competing ways to end the same block, which is
// how the old "Finish" / "Remove" pair was read.
export default class extends Controller {
  static targets = ["prompt", "choice"]

  reveal() {
    this.promptTarget.hidden = true
    this.choiceTarget.hidden = false
    this.choiceTarget.querySelector("button")?.focus()
  }

  cancel() {
    this.choiceTarget.hidden = true
    this.promptTarget.hidden = false
    this.promptTarget.querySelector("button")?.focus()
  }
}
