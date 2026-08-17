import { Controller } from "@hotwired/stimulus"

// Keeps a form's Save disabled and its Cancel hidden until one of its fields
// actually changed. Put on a <form> whose Save button is its own -- the property
// settings page has four such forms, and a Save that is always live cannot say
// which of them has anything to save.
//
// The submit button is enabled in the markup and disabled here on connect, so a
// page without JS keeps a working Save rather than a permanently dead one.
// Cancel is the reverse: it is a native reset that only means anything once the
// form is dirty, and without JS there is nothing to discard mid-page anyway.
export default class extends Controller {
  static targets = ["submit", "cancel"]

  connect() {
    this.snapshot = this.serialize()
    this.refresh()
  }

  // The PanelsUI select menus and the Tom Select-backed combobox/multi-select
  // both write to their native control and dispatch bubbling input/change, so
  // listening at the form catches every field regardless of how it is drawn.
  refresh() {
    const dirty = this.serialize() !== this.snapshot

    this.submitTargets.forEach((button) => {
      button.disabled = !dirty
    })
    this.cancelTargets.forEach((button) => {
      button.hidden = !dirty
    })
  }

  // The reset event fires before the browser restores the fields, and the
  // enhanced controls resync themselves a frame later — so read the form back
  // only once both have settled.
  restore() {
    requestAnimationFrame(() => this.refresh())
  }

  serialize() {
    return JSON.stringify(Array.from(new FormData(this.element)))
  }
}
