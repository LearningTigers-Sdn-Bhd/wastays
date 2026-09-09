import { Controller } from "@hotwired/stimulus"

const EXIT_DURATION_MS = 250

// Bottom sheet for the concierge recommendation categories.
//
// Deliberately not PanelsUI::Sheet: that component is opened with the native
// command/commandfor invoker, which is Safari 18.4 and newer, and the concierge
// page opts out of the browser version check precisely because guests arrive on
// old phones. Native <dialog> alone is supported far further back, and this
// controller adds only the slide and the scroll lock on top of it.
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.closeTimer = null
  }

  disconnect() {
    this.clearTimer()
    this.unlockScroll()
  }

  open() {
    const dialog = this.dialogTarget
    if (dialog.open) return

    this.clearTimer()

    if (typeof dialog.showModal === "function") {
      dialog.showModal()
    } else {
      // No modal support: still usable, just without the top layer.
      dialog.setAttribute("open", "")
    }

    this.lockScroll()
    // Two frames: the first paints the sheet off-screen, the second animates it
    // in. One frame is not always enough once the dialog enters the top layer.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => dialog.setAttribute("data-open", ""))
    })
  }

  close() {
    const dialog = this.dialogTarget
    if (!dialog.open) return

    dialog.removeAttribute("data-open")

    if (this.prefersReducedMotion()) {
      dialog.close()
      return
    }

    this.clearTimer()
    this.closeTimer = window.setTimeout(() => dialog.close(), EXIT_DURATION_MS)
  }

  // Esc and the native close event both land here, including the paths that
  // skip our own close().
  onClose() {
    this.clearTimer()
    this.dialogTarget.removeAttribute("data-open")
    this.unlockScroll()
  }

  // The dialog element itself is the backdrop; the panel inside it is not.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  lockScroll() {
    this.previousOverflow = document.documentElement.style.overflow
    document.documentElement.style.overflow = "hidden"
  }

  unlockScroll() {
    document.documentElement.style.overflow = this.previousOverflow || ""
  }

  prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  clearTimer() {
    if (this.closeTimer) {
      window.clearTimeout(this.closeTimer)
      this.closeTimer = null
    }
  }
}
