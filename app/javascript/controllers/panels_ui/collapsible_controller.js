import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--collapsible
//
// shadcn/Radix-style disclosure state for server-rendered Rails markup. The
// controller mirrors `open` to data-state + aria-expanded, exposes open/close
// methods for coordinating controllers, and keeps closing content inert until
// its height animation has completed.
export default class extends Controller {
  static targets = ["trigger", "content", "contentInner"]
  static values = {
    open: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false }
  }

  connect() {
    this.connected = true
    this.contentTarget.addEventListener("animationend", this.finishAnimation)
    this.resizeObserver = new ResizeObserver(() => this.measure())
    this.resizeObserver.observe(this.contentInnerTarget)
    this.sync({ animate: false, notify: false })
  }

  disconnect() {
    this.connected = false
    this.resizeObserver?.disconnect()
    this.contentTarget.removeEventListener("animationend", this.finishAnimation)
    window.clearTimeout(this.hideTimer)
  }

  toggle(event) {
    event?.preventDefault()
    if (this.disabledValue || this.triggerTarget.getAttribute("aria-disabled") === "true") return

    this.openValue = !this.openValue
  }

  open() {
    if (!this.disabledValue) this.openValue = true
  }

  close() {
    if (!this.disabledValue) this.openValue = false
  }

  openValueChanged() {
    if (this.connected) this.sync({ animate: true, notify: true })
  }

  sync({ animate, notify }) {
    const state = this.openValue ? "open" : "closed"
    const shouldAnimate = animate && !this.reducedMotion

    window.clearTimeout(this.hideTimer)
    if (this.openValue) this.contentTarget.hidden = false
    this.measure()

    this.contentTarget.toggleAttribute("data-collapsible-animate", shouldAnimate)
    this.element.dataset.state = state
    this.triggerTarget.dataset.state = state
    this.contentTarget.dataset.state = state
    this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))

    if (this.openValue) {
      this.contentTarget.inert = false
    } else {
      if (this.contentTarget.contains(document.activeElement)) this.triggerTarget.focus()
      this.contentTarget.inert = true

      if (!shouldAnimate) {
        this.contentTarget.hidden = true
      } else {
        // animationend is the normal path; the timeout covers browsers that do
        // not emit it after an interrupted animation or stylesheet replacement.
        this.hideTimer = window.setTimeout(() => this.hideClosedContent(), 250)
      }
    }

    if (notify) this.dispatch("change", { detail: { open: this.openValue } })
  }

  measure() {
    const height = this.contentInnerTarget.scrollHeight
    this.contentTarget.style.setProperty("--panel-collapsible-content-height", `${height}px`)
  }

  finishAnimation = (event) => {
    if (event.target !== this.contentTarget || !event.animationName.startsWith("panel-collapsible-")) return
    if (event.animationName === "panel-collapsible-up") this.hideClosedContent()
    this.contentTarget.removeAttribute("data-collapsible-animate")
  }

  hideClosedContent() {
    if (!this.openValue) this.contentTarget.hidden = true
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
