import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "frame"]
  static classes = ["open", "closed"]
  static values = { variant: { type: String, default: "right" } }

  connect() {
    this.lifecycle = new AbortController()
    this.pendingVariant = this.variantValue
    document.addEventListener("click", (event) => this.handleTriggerClick(event), { signal: this.lifecycle.signal })
    document.addEventListener("keydown", (event) => this.handleKeydown(event), { signal: this.lifecycle.signal })
    window.addEventListener("offcanvas:load", (event) => this.load(event), { signal: this.lifecycle.signal })

    // Listen synchronously for clicks on close triggers to bypass Stimulus race conditions
    this.element.addEventListener("click", (event) => {
      const closeTrigger = event.target.closest('[data-action*="offcanvas#close"]')
      if (closeTrigger) {
        event.preventDefault()
        this.close()
      }
    }, { signal: this.lifecycle.signal })

    // Listen for turbo frame loads to open the drawer
    this.element.addEventListener("turbo:frame-load", (event) => {
      if (event.target.id === this.frameTarget.id) {
        const variant = event.target.dataset.offcanvasVariant || this.pendingVariant || this.variantValue
        this.panelTarget.setAttribute("aria-label", event.target.dataset.offcanvasLabel || "Booking details")
        this.applyVariant(variant)
        this.open()
      }
    }, { signal: this.lifecycle.signal })
  }

  disconnect() {
    this.lifecycle?.abort()
    clearTimeout(this.closeTimeout)
    clearTimeout(this.completeTimeout)
    clearTimeout(this.openTimeout)
  }

  handleTriggerClick(event) {
    const trigger = event.target.closest(`[data-turbo-frame="${this.frameTarget.id}"]`)
    if (!trigger) return

    // Replacing content inside an open drawer is a continuation of the same
    // interaction. Keep the external opener so completion and cancellation can
    // restore focus after the nested link itself leaves the DOM.
    const navigatingInsideOpenDrawer = this.element.contains(trigger) && this.element.classList.contains(this.openClass)
    if (navigatingInsideOpenDrawer) {
      this.pendingVariant = trigger.dataset.offcanvasVariant || this.pendingVariant || this.variantValue
      setTimeout(() => window.dispatchEvent(new CustomEvent("dropdown:close-all")), 0)
      return
    }

    this.trigger = trigger.closest("[data-controller~='panels-ui--dropdown-menu']")
      ?.querySelector("[data-panels-ui--dropdown-menu-target='trigger']") || trigger
    this.pendingVariant = trigger.dataset.offcanvasVariant || this.variantValue
    this.returnFocusElement = this.trigger
    this.returnFocusId = this.trigger.id || document.activeElement?.id
    setTimeout(() => window.dispatchEvent(new CustomEvent("dropdown:close-all")), 0)
  }

  load(event) {
    const { url, variant, returnFocusId, drawerId } = event.detail || {}
    if (!url) return
    if (drawerId && drawerId !== this.frameTarget.id) return

    this.pendingVariant = variant || this.variantValue
    this.returnFocusElement = document.getElementById(returnFocusId) || document.activeElement
    this.returnFocusId = returnFocusId || document.activeElement?.id
    this.frameTarget.src = url
  }

  open() {
    clearTimeout(this.closeTimeout)
    clearTimeout(this.openTimeout)
    window.dispatchEvent(new CustomEvent("offcanvas:open"))
    this.element.classList.replace(this.closedClass, this.openClass)
    // Block interaction until the slide-in transition finishes, so a click during
    // the animation can't land on a row that hasn't reached its final position yet.
    this.panelTarget.classList.add("pointer-events-none")
    // Small delay to ensure display:block is applied before transition
    requestAnimationFrame(() => {
      this.panelTarget.classList.remove(this.closedTransformClass)
      this.panelTarget.classList.add(this.openTransformClass)
    })
    const initialFocus = this.focusableElements[0] || this.panelTarget
    initialFocus.focus()
    this.openTimeout = setTimeout(() => {
      this.panelTarget.classList.remove("pointer-events-none")
    }, 300)
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.panelTarget.classList.remove(this.openTransformClass)
    this.panelTarget.classList.add(this.closedTransformClass)
    
    // Wait for transition then hide
    this.closeTimeout = setTimeout(() => {
      this.element.classList.replace(this.openClass, this.closedClass)
      this.frameTarget.src = "" // Clear the frame content
      this.frameTarget.innerHTML = `
        <div class="flex items-center justify-center h-full">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-foreground"></div>
        </div>
      `
      document.body.classList.remove("overflow-hidden")
      this.restoreFocus()
      window.dispatchEvent(new CustomEvent("offcanvas:closed", { detail: { returnFocusId: this.returnFocusId } }))
    }, 300)
  }

  handleKeydown(event) {
    if (!this.element.classList.contains(this.openClass) || !this.topmostOpen) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key !== "Tab") return

    const elements = this.focusableElements
    if (elements.length === 0) {
      event.preventDefault()
      this.panelTarget.focus()
      return
    }

    const first = elements[0]
    const last = elements[elements.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  complete(url) {
    this.close()
    this.completeTimeout = setTimeout(() => {
      if (url) Turbo.visit(url, { action: "replace" })
    }, 325)
  }

  applyVariant(variant) {
    this.currentVariant = ["fullscreen-bottom", "compact-right"].includes(variant) ? variant : "right"

    this.panelTarget.classList.remove(
      "inset-y-0", "right-0",
      "sm:w-[600px]", "md:w-[800px]", "lg:w-[1000px]",
      "sm:w-[480px]", "md:w-[520px]", "lg:w-[560px]",
      "translate-x-full", "translate-x-0",
      "inset-x-0", "bottom-0", "h-screen", "translate-y-full", "translate-y-0"
    )

    const isOpen = this.element.classList.contains(this.openClass)
    const transformClass = isOpen ? this.openTransformClass : this.closedTransformClass

    if (this.currentVariant === "fullscreen-bottom") {
      this.panelTarget.classList.add("inset-x-0", "bottom-0", "h-screen", "w-full", transformClass)
    } else if (this.currentVariant === "compact-right") {
      this.panelTarget.classList.add("inset-y-0", "right-0", "w-full", "sm:w-[480px]", "md:w-[520px]", "lg:w-[560px]", transformClass)
    } else {
      this.panelTarget.classList.add("inset-y-0", "right-0", "w-full", "sm:w-[600px]", "md:w-[800px]", "lg:w-[1000px]", transformClass)
    }
  }

  restoreFocus() {
    const target = (this.returnFocusElement?.isConnected && this.returnFocusElement) || document.getElementById(this.returnFocusId)
    target?.focus({ preventScroll: true })
  }

  get closedTransformClass() {
    return this.currentVariant === "fullscreen-bottom" ? "translate-y-full" : "translate-x-full"
  }

  get openTransformClass() {
    return this.currentVariant === "fullscreen-bottom" ? "translate-y-0" : "translate-x-0"
  }

  get focusableElements() {
    return [...this.panelTarget.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )].filter((element) => element.getClientRects().length > 0)
  }

  get topmostOpen() {
    const openDrawers = [...document.querySelectorAll('[data-controller~="offcanvas"]')]
      .filter((element) => !element.classList.contains(this.closedClass))
    return openDrawers.at(-1) === this.element
  }
}
