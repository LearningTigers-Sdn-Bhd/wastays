import { Controller } from "@hotwired/stimulus"

// Keeps a saved slot's Save and Discard buttons out of the way until the row
// actually differs from what was saved, so a list of slots reads as settings
// rather than a wall of buttons.
//
// Dirty is a comparison against the values the row loaded with, not a one-way
// flag: tick a meal and untick it again and the row is clean once more.
// Discard resets the form, which the time picker listens for to restore its
// own display.
//
// Both controls in the row bubble input/change events -- the time picker
// dispatches them from its hidden input -- so one listener on the row covers
// the time and all three meal checkboxes.
export default class extends Controller {
  static targets = ["form", "save", "discard"]

  connect() {
    if (!this.hasFormTarget) return
    this.pristine = this.serialize()
    this.sync()
  }

  sync() {
    if (!this.hasFormTarget) return
    const dirty = this.serialize() !== this.pristine
    if (this.hasSaveTarget) this.saveTarget.hidden = !dirty
    if (this.hasDiscardTarget) this.discardTarget.hidden = !dirty
  }

  discard() {
    this.formTarget.reset()
    this.sync()
  }

  serialize() {
    return new URLSearchParams(new FormData(this.formTarget)).toString()
  }
}
