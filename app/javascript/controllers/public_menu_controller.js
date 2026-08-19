import { Controller } from "@hotwired/stimulus"

// A short list of actions behind one button, on a guest-facing page.
//
// Small on purpose. The portal's menu positions itself with floating-ui
// because it can open anywhere on a dense screen; this one hangs off a fixed
// corner of the chat bar, so the stylesheet already knows where it goes.
//
// What is left is the part a menu cannot skip: it calls itself a menu, so it
// has to behave like one. The arrow keys move between items, Home and End go
// to the ends, Escape hands the focus back, and Tab leaves -- a role="menu"
// that only answers to Tab is a widget that lies about what it is.
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
    this.focusItem(0)
  }

  close() {
    if (!this.hasMenuTarget || !this.open) return

    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  onKeydown(event) {
    if (!this.open) {
      // Down on the closed trigger opens the menu on its first item, which is
      // how every other menu on the web behaves.
      if (event.key === "ArrowDown" && event.target === this.triggerTarget) {
        event.preventDefault()
        this.show()
      }
      return
    }

    switch (event.key) {
      case "Escape":
        event.stopPropagation()
        this.close()
        this.triggerTarget.focus()
        break
      case "ArrowDown":
        event.preventDefault()
        this.focusItem(this.currentIndex + 1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.focusItem(this.currentIndex - 1)
        break
      case "Home":
        event.preventDefault()
        this.focusItem(0)
        break
      case "End":
        event.preventDefault()
        this.focusItem(this.items.length - 1)
        break
      case "Tab":
        // Leaving is leaving: the menu must not still be open behind whatever
        // the guest lands on next.
        this.close()
        break
    }
  }

  // pointerdown rather than click: a menu that is still open while the guest
  // is pressing something behind it has already been dismissed as far as they
  // are concerned.
  onWindowPointerDown(event) {
    if (!this.open || this.element.contains(event.target)) return

    this.close()
  }

  focusItem(index) {
    const items = this.items
    if (items.length === 0) return

    // Wraps, so holding one arrow key cannot strand you at an end.
    items[(index + items.length) % items.length].focus()
  }

  get items() {
    return Array.from(this.menuTarget.querySelectorAll("[role='menuitem']"))
  }

  get currentIndex() {
    return this.items.indexOf(document.activeElement)
  }

  get open() {
    return this.hasMenuTarget && !this.menuTarget.hidden
  }
}
