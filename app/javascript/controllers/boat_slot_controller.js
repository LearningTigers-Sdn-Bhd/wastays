import { Controller } from "@hotwired/stimulus"

// Keeps a saved slot's Discard button out of the way until the row actually
// differs from what was saved, so a list of slots reads as settings rather
// than a wall of buttons. Saving itself happens for every dirty row at once,
// from the page-level "Save changes" bar (see boat_slots_bulk_controller).
//
// Dirty is a comparison against the values the row loaded with, not a one-way
// flag: tick a meal and untick it again and the row is clean once more.
// Discard resets the form, which the time picker listens for to restore its
// own display. The row also exposes its dirty state as a data attribute so
// the bulk controller can find every changed row without re-deriving it.
//
// Both controls in the row bubble input/change events -- the time picker
// dispatches them from its hidden input -- so one listener on the row covers
// the time and all three meal checkboxes.
export default class extends Controller {
  static targets = ["form", "discard"]

  connect() {
    if (!this.hasFormTarget) return
    this.pristine = this.serialize()
    this.sync()
  }

  sync() {
    if (!this.hasFormTarget) return
    const dirty = this.serialize() !== this.pristine
    this.element.dataset.dirty = dirty
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
