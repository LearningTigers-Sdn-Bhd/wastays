import { Controller } from "@hotwired/stimulus"
import { arrow, autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"
import { positionArrow } from "controllers/panels_ui/support/floating_arrow"

// Text-only tooltip. A stripped-down sibling of panels-ui--dropdown-menu: reuses
// the same @floating-ui positioning, drops all menu/roving/selection machinery.

export default class extends Controller {
  static targets = ["bubble", "arrow"]
  static values = {
    placement: { type: String, default: "top" },
    offset: { type: Number, default: 6 },
    delay: { type: Number, default: 120 },
    tooltipId: String
  }

  connect() {
    this.cleanupPosition = null
    this.showTimer = null
    this.onOtherLayerOpen = this.handleOtherLayerOpen.bind(this)
    window.addEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
    // aria-describedby belongs on the focusable trigger itself, not the wrapper.
    this.trigger = this.element.querySelector(":scope > :not([data-panels-ui--tooltip-target='bubble'])")
    this.trigger?.setAttribute("aria-describedby", this.tooltipIdValue)
  }

  disconnect() {
    this.cancelShow()
    window.removeEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
    this.stopPositioning()
    if (this.isOpen) this.bubbleTarget.hidePopover()
  }

  show() {
    if (this.isOpen) return
    this.cancelShow()
    this.showTimer = setTimeout(() => this.reveal(), this.delayValue)
  }

  hide() {
    this.cancelShow()
    if (!this.isOpen) return
    this.bubbleTarget.dataset.state = "closed"
    this.bubbleTarget.hidePopover()
    this.stopPositioning()
  }

  onKeydown(event) {
    if (event.key === "Escape") this.hide()
  }

  reveal() {
    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: this } }))
    this.bubbleTarget.showPopover()
    this.bubbleTarget.dataset.state = "open"
    this.startPositioning()
  }

  get isOpen() {
    return this.bubbleTarget.matches(":popover-open")
  }

  cancelShow() {
    clearTimeout(this.showTimer)
    this.showTimer = null
  }

  handleOtherLayerOpen(event) {
    if (event.detail?.controller !== this) this.hide()
  }

  startPositioning() {
    this.stopPositioning()
    const reference = this.trigger ?? this.element
    this.cleanupPosition = autoUpdate(reference, this.bubbleTarget, () => this.position(reference))
  }

  stopPositioning() {
    this.cleanupPosition?.()
    this.cleanupPosition = null
  }

  position(reference) {
    const middleware = [offset(this.offsetValue), flip(), shift({ padding: 8 })]
    if (this.hasArrowTarget) middleware.push(arrow({ element: this.arrowTarget, padding: 6 }))

    computePosition(reference, this.bubbleTarget, {
      placement: this.placementValue,
      strategy: "fixed",
      middleware
    }).then(({ x, y, placement, middlewareData }) => {
      Object.assign(this.bubbleTarget.style, { left: `${x}px`, top: `${y}px` })
      if (this.hasArrowTarget) positionArrow(this.arrowTarget, placement, middlewareData.arrow)
    })
  }
}
