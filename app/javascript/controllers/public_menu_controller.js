import { Controller } from "@hotwired/stimulus"

// A short list of actions behind one button, on a guest-facing page.
//
// Small on purpose. The portal's menu positions itself with floating-ui
// because it can open anywhere on a dense screen; this one hangs off a fixed
// corner of the chat bar, so the stylesheet already knows where it goes and
// all that is left is opening, closing, and not trapping anyone inside it.
export default class extends Controller {
  static targets = ["trigger", "menu"]

  disconnect() {
    this.close()
  }

  toggle() {
    this.open ? this.close() : this.show()
  }

  show() {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.menuTarget.querySelector("[role='menuitem']")?.focus()
  }

  close() {
    if (!this.hasMenuTarget || !this.open) return

    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  // Escape closes and hands the focus back, rather than leaving it on an item
  // that is no longer on screen.
  onKeydown(event) {
    if (event.key !== "Escape" || !this.open) return

    event.stopPropagation()
    this.close()
    this.triggerTarget.focus()
  }

  // pointerdown rather than click: a menu that is still open while the guest
  // is pressing something behind it has already been dismissed as far as they
  // are concerned.
  onWindowPointerDown(event) {
    if (!this.open || this.element.contains(event.target)) return

    this.close()
  }

  get open() {
    return this.hasMenuTarget && !this.menuTarget.hidden
  }
}
