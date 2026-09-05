import { Controller } from "@hotwired/stimulus"

// Keeps a form's Save disabled and its Cancel hidden until one of its fields
// actually changed. Put on a <form> whose Save button is its own -- the property
// settings page has four such forms, and a Save that is always live cannot say
// which of them has anything to save.
//
// Save and Cancel both start switched off in the markup, because a form that
// has just loaded has nothing to save and nothing to discard. Rendering Save
// live and disabling it here flashed an enabled button on every page load, once
// per form on a page that carries several.
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
    const entries = Array.from(new FormData(this.element), ([name, value]) => {
      if (!(value instanceof File)) return [name, value]
      if (value.name === "" && value.size === 0) return [name, null]

      return [name, {
        name: value.name,
        size: value.size,
        type: value.type,
        lastModified: value.lastModified
      }]
    })

    return JSON.stringify(entries)
  }
}
