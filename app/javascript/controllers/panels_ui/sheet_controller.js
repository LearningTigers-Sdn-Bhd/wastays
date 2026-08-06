import { Controller } from "@hotwired/stimulus"
import { isTopOverlay, lockScroll, unlockScroll } from "controllers/panels_ui/support/overlay"

const EXIT_DURATION_MS = 300
const EXIT_FALLBACK_MS = EXIT_DURATION_MS + 50

// Identifier: panels-ui--sheet (attached directly to the native <dialog>).
// Native dialog owns the top layer, inert background, focus trap, and focus
// restoration. This controller adds slide motion and shared overlay-stack rules.
export default class extends Controller {
  static targets = ["panel", "initialFocus"]
  static values = { dismissible: { type: Boolean, default: true } }

  connect() {
    this.closing = false
    this.observer = new MutationObserver(() => {
      if (this.element.open) this.onOpen()
    })
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["open"] })
    if (this.element.open) this.onOpen()
  }

  disconnect() {
    this.observer?.disconnect()
    this.cancelOpenFrame()
    this.cancelCloseWait()
    this.element.removeAttribute("data-panels-open")
    unlockScroll(this.element)
    if (this.element.open) this.element.close()
  }

  open() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    if (!this.element.open || this.closing || !isTopOverlay(this.element)) return

    this.closing = true
    this.cancelOpenFrame()

    const wasVisiblyOpen = this.element.hasAttribute("data-panels-open")
    this.element.removeAttribute("data-panels-open")

    if (!wasVisiblyOpen || this.prefersReducedMotion()) {
      this.finishClose()
      return
    }

    this.handleTransitionEnd = (event) => {
      if (event.target === this.element && event.propertyName === "transform") this.finishClose()
    }
    this.element.addEventListener("transitionend", this.handleTransitionEnd)
    this.closeTimer = window.setTimeout(() => this.finishClose(), EXIT_FALLBACK_MS)
  }

  onOpen() {
    if (this.element.hasAttribute("data-panels-open") || this.openFrame) return

    this.closing = false
    lockScroll(this.element)

    if (this.hasPanelTarget && !this.element.querySelector("[autofocus]")) {
      const target = this.hasInitialFocusTarget ? this.initialFocusTarget : this.panelTarget
      target.focus()
    }

    // Commit the off-canvas transform before activating the transition.
    this.element.getBoundingClientRect()
    this.openFrame = window.requestAnimationFrame(() => {
      this.openFrame = null
      if (this.element.open && !this.closing) {
        this.element.setAttribute("data-panels-open", "")
        this.element.dispatchEvent(new CustomEvent("panels-ui:sheet-open", { bubbles: true }))
      }
    })
  }

  backdropClose(event) {
    if (this.dismissibleValue && isTopOverlay(this.element) && event.target === this.element) this.close()
  }

  onCancel(event) {
    // Prevent native immediate close so the sheet can animate out.
    event.preventDefault()
    if (this.dismissibleValue && isTopOverlay(this.element)) this.close()
  }

  onClose() {
    this.cancelOpenFrame()
    this.cancelCloseWait()
    this.closing = false
    this.element.removeAttribute("data-panels-open")
    unlockScroll(this.element)
  }

  finishClose() {
    if (!this.closing) return

    this.cancelCloseWait()
    this.closing = false
    if (this.element.open) {
      // Release the scroll lock synchronously here, before element.close().
      // The native `close` event (wired to onClose) is dispatched via a queued
      // task, so relying on it alone leaves a window where the dialog is already
      // closed and focus restored but the body is still scroll-locked. onClose
      // stays as an idempotent safety net for closes that bypass finishClose.
      unlockScroll(this.element)
      this.element.close()
      window.dispatchEvent(new CustomEvent("panels-ui:sheet-closed"))
    }
  }

  cancelOpenFrame() {
    if (!this.openFrame) return

    window.cancelAnimationFrame(this.openFrame)
    this.openFrame = null
  }

  cancelCloseWait() {
    if (this.handleTransitionEnd) {
      this.element.removeEventListener("transitionend", this.handleTransitionEnd)
      this.handleTransitionEnd = null
    }
    if (this.closeTimer) {
      window.clearTimeout(this.closeTimer)
      this.closeTimer = null
    }
  }

  prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true
  }
}
