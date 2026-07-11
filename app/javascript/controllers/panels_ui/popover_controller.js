import { Controller } from "@hotwired/stimulus"
import { arrow, autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"
import { createTrap, onDismiss } from "controllers/panels_ui/support/overlay"
import { positionArrow } from "controllers/panels_ui/support/floating_arrow"

// Identifier: panels-ui--popover
//
// Click- (or hover-) triggered container yielding arbitrary content. Reuses the
// @floating-ui positioning spine and shared bordered arrow; dismissal (Escape + outside
// pointer) comes from support/overlay's onDismiss. `focus: true` adds a focus trap only —
// no scroll lock, no inert backdrop (see PanelsUI::Popover). One layer open at a time via
// the shared `panels-ui:layer-open` channel.
export default class extends Controller {
  static targets = ["trigger", "panel", "arrow"]
  static values = {
    placement: { type: String, default: "bottom" },
    offset: { type: Number, default: 8 },
    delay: { type: Number, default: 120 },
    closeDelay: { type: Number, default: 0 },
    triggerOn: { type: String, default: "click" },
    focus: { type: Boolean, default: false }
  }

  connect() {
    this.cleanupPosition = null
    this.cleanupDismiss = null
    this.trap = null
    this.showTimer = null
    this.closeTimer = null
    this.pinned = false
    this.onOtherLayerOpen = this.handleOtherLayerOpen.bind(this)
    window.addEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
  }

  disconnect() {
    window.removeEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
    this.cancelShow()
    this.cancelClose()
    this.trap?.deactivate()
    this.stopPositioning()
    this.cleanupDismiss?.()
    if (this.isOpen) this.panelTarget.hidePopover()
  }

  // ── Open / close ─────────────────────────────────────────────────────────────
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.triggerOnValue === "hover") {
      if (this.pinned) {
        this.close(true)
      } else {
        this.pinned = true
        this.open()
      }
      return
    }

    this.isOpen ? this.close(true) : this.open()
  }

  onTriggerKeydown(event) {
    if (!["Enter", " ", "ArrowDown", "ArrowUp"].includes(event.key)) return
    event.preventDefault()
    this.open()
  }

  open() {
    if (this.isOpen) return
    this.cancelClose()

    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: this } }))
    this.panelTarget.showPopover()
    this.panelTarget.dataset.state = "open"
    this.triggerTarget?.setAttribute("aria-expanded", "true")
    this.startPositioning()

    // onDismiss owns Escape + outside-pointer for both modes; createTrap is configured
    // to defer dismissal to it (escapeDeactivates:false, allowOutsideClick:true).
    this.cleanupDismiss = onDismiss(this.element, {
      onEscape: () => this.close(true),
      onOutside: () => this.close()
    })

    if (this.focusValue) {
      this.trap = createTrap(this.panelTarget)
      this.trap.activate()
    }
  }

  close(restoreFocus = false) {
    this.cancelShow()
    this.cancelClose()
    this.pinned = false
    if (!this.isOpen) return

    this.trap?.deactivate()
    this.trap = null
    this.panelTarget.dataset.state = "closed"
    this.panelTarget.hidePopover()
    this.triggerTarget?.setAttribute("aria-expanded", "false")
    this.stopPositioning()
    this.cleanupDismiss?.()
    this.cleanupDismiss = null
    // A focus trap moved focus away, so always restore it; otherwise only when asked.
    if (restoreFocus || this.focusValue) this.triggerTarget?.focus()
  }

  // ── Hover trigger (only wired when trigger_on: :hover) ─────────────────────────
  show() {
    this.cancelClose()
    if (this.isOpen) return
    this.cancelShow()
    this.showTimer = setTimeout(() => this.open(), this.delayValue)
  }

  hide(event) {
    this.cancelShow()
    if (this.pinned) return
    if (event?.type === "focusout" && this.element.contains(event.relatedTarget)) return
    this.cancelClose()
    this.closeTimer = setTimeout(() => this.close(), this.closeDelayValue)
  }

  cancelShow() {
    clearTimeout(this.showTimer)
    this.showTimer = null
  }

  cancelClose() {
    clearTimeout(this.closeTimer)
    this.closeTimer = null
  }

  handleOtherLayerOpen(event) {
    if (event.detail?.controller !== this) this.close()
  }

  get isOpen() {
    return this.panelTarget.matches(":popover-open")
  }

  // ── Positioning ────────────────────────────────────────────────────────────────
  startPositioning() {
    this.stopPositioning()
    const reference = this.triggerTarget ?? this.element
    this.cleanupPosition = autoUpdate(reference, this.panelTarget, () => this.position(reference))
  }

  stopPositioning() {
    this.cleanupPosition?.()
    this.cleanupPosition = null
  }

  position(reference) {
    const middleware = [offset(this.offsetValue), flip(), shift({ padding: 8 })]
    if (this.hasArrowTarget) middleware.push(arrow({ element: this.arrowTarget, padding: 6 }))

    computePosition(reference, this.panelTarget, {
      placement: this.placementValue,
      strategy: "fixed",
      middleware
    }).then(({ x, y, placement, middlewareData }) => {
      Object.assign(this.panelTarget.style, { left: `${x}px`, top: `${y}px` })
      if (this.hasArrowTarget) positionArrow(this.arrowTarget, placement, middlewareData.arrow)
    })
  }
}
