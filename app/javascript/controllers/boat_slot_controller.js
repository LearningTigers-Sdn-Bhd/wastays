import { Controller } from "@hotwired/stimulus"

// Keeps a slot row's Save button out of the way until something actually
// changes, so a list of slots reads as settings rather than a wall of buttons.
//
// Both controls in the row bubble input/change events -- the time picker
// dispatches them from its hidden input -- so one listener on the row covers
// the time and all three meal checkboxes.
export default class extends Controller {
  static targets = ["save"]

  connect() {
    this.pristine()
  }

  markDirty() {
    this.saveTarget.hidden = false
  }

  pristine() {
    this.saveTarget.hidden = true
  }
}
