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
    focus: { type: Boolean, default: false },
    owner: String
  }

  connect() {
    this.cleanupPosition = null
    this.cleanupDismiss = null
    this.trap = null
    this.showTimer = null
    this.closeTimer = null
    this.pinned = false
    this.onOtherLayerOpen = this.handleOtherLayerOpen.bind(this)
    this.onLayerClose = this.handleLayerClose.bind(this)
    window.addEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
    window.addEventListener("panels-ui:layer-close", this.onLayerClose)
  }

  disconnect() {
    window.removeEventListener("panels-ui:layer-open", this.onOtherLayerOpen)
    window.removeEventListener("panels-ui:layer-close", this.onLayerClose)
    this.cancelShow()
    this.cancelClose()
    this.trap?.deactivate()
    this.stopPositioning()
    this.cleanupDismiss?.()
    if (this.isOpen) {
      if (this.openedEmbedded) delete this.panelTarget.dataset.embeddedOpen
      else this.panelTarget.hidePopover()
    }
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

    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: this, owner: this.hasOwnerValue ? this.ownerValue : null } }))
    this.openedEmbedded = this.embeddedMobile
    if (this.openedEmbedded) this.panelTarget.dataset.embeddedOpen = "true"
    else this.panelTarget.showPopover()
    this.panelTarget.dataset.state = "open"
    this.element.dispatchEvent(new CustomEvent("panels-ui:popover-open", { bubbles: true }))
    this.triggerTarget?.setAttribute("aria-expanded", "true")
    this.startPositioning()

    // onDismiss owns Escape + outside-pointer for both modes; createTrap is configured
    // to defer dismissal to it (escapeDeactivates:false, allowOutsideClick:true).
    this.cleanupDismiss = onDismiss(this.element, {
      onEscape: () => { if (!this.hasOpenOwnedPanel) this.close(true) },
      onOutside: (event) => {
        if (this.ownedOpenPanelContains(event.target)) return
        this.close()
      }
    })

    if (this.focusValue) {
      // Focus the dialog surface first. This avoids painting a misleading focus ring
      // on the first calendar navigation control when the popover was pointer-opened;
      // keyboard users reach that control with the next Tab press.
      this.trap = createTrap(this.panelTarget, { initialFocus: this.panelTarget })
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
    if (this.openedEmbedded) delete this.panelTarget.dataset.embeddedOpen
    else this.panelTarget.hidePopover()
    this.openedEmbedded = false
    this.triggerTarget?.setAttribute("aria-expanded", "false")
    this.stopPositioning()
    this.cleanupDismiss?.()
    this.cleanupDismiss = null
    window.dispatchEvent(new CustomEvent("panels-ui:layer-close", { detail: { controller: this, owner: this.hasOwnerValue ? this.ownerValue : null } }))
    // Resume an owning trap before restoring focus so it does not pull focus back to
    // the parent surface after the child trigger has been focused.
    if (restoreFocus || this.focusValue) {
      if (this.hasOwnerValue) window.setTimeout(() => this.triggerTarget?.focus(), 0)
      else this.triggerTarget?.focus()
    }
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
    const other = event.detail?.controller
    if (other === this) return
    if (event.detail?.owner === this.panelTarget.id) {
      this.trap?.pause()
      return
    }
    if (this.hasOwnerValue && other?.panelTarget?.id === this.ownerValue) return
    this.close()
  }

  handleLayerClose(event) {
    if (event.detail?.owner === this.panelTarget.id && this.isOpen) {
      this.trap?.unpause()
      const trigger = event.detail.controller?.triggerTarget
      window.setTimeout(() => trigger?.focus(), 0)
    }
  }

  get hasOpenOwnedPanel() {
    return [...document.querySelectorAll(`[data-panels-ui--popover-owner-value="${this.panelTarget.id}"]`)]
      .some((root) => root.querySelector(":scope > .popover[data-state='open']"))
  }

  ownedOpenPanelContains(target) {
    return [...document.querySelectorAll(`[data-panels-ui--popover-owner-value="${this.panelTarget.id}"]`)]
      .some((root) => root.querySelector(":scope > .popover[data-state='open']")?.contains(target))
  }

  get isOpen() {
    return this.panelTarget.matches(":popover-open") || this.panelTarget.dataset.embeddedOpen === "true"
  }

  get embeddedMobile() {
    return this.hasOwnerValue && window.matchMedia("(max-width: 639px)").matches
  }

  // ── Positioning ────────────────────────────────────────────────────────────────
  startPositioning() {
    this.stopPositioning()
    if (this.embeddedMobile) return
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
      // Custom elements such as Cally can grow after their first measurement. Clamp
      // the final coordinates against the upgraded panel size as a last collision
      // guard; autoUpdate will continue to refine placement after later resizes.
      const rect = this.panelTarget.getBoundingClientRect()
      const padding = 8
      const clampedX = Math.max(padding, Math.min(x, window.innerWidth - rect.width - padding))
      const clampedY = Math.max(padding, Math.min(y, window.innerHeight - rect.height - padding))
      Object.assign(this.panelTarget.style, { left: `${clampedX}px`, top: `${clampedY}px` })
      if (this.hasArrowTarget) positionArrow(this.arrowTarget, placement, middlewareData.arrow)
    })
  }
}
