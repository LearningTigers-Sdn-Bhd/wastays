import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--sheet-frame
//
// Wraps a PanelsUI::Sheet that is lazy-loaded into a <turbo-frame>. Auto-opens
// the native <dialog> on connect (the fragment arrives over Turbo, so there is
// no native `command="show-modal"` invoker) and clears the enclosing frame when
// the sheet closes so the same trigger link re-fetches a fresh form next time.
export default class extends Controller {
  connect() {
    this.dialog = this.element.querySelector("dialog")
    if (!this.dialog) return

    // The native `close` event does not bubble, so it must be bound directly on
    // the dialog rather than through a Stimulus data-action on this wrapper.
    this.onClose = () => {
      const frame = this.element.closest("turbo-frame")
      if (!frame) return
      frame.removeAttribute("src")
      frame.replaceChildren()
    }
    this.dialog.addEventListener("close", this.onClose)

    if (!this.dialog.open) this.dialog.showModal()
  }

  disconnect() {
    this.dialog?.removeEventListener("close", this.onClose)
  }
}
