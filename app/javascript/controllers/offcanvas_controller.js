import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "frame"]
  static classes = ["open", "closed"]
  static values = { variant: { type: String, default: "right" } }

  connect() {
    this.pendingVariant = this.variantValue
    this.handleTriggerClick = this.handleTriggerClick.bind(this)

    document.addEventListener("click", this.handleTriggerClick)

    // Listen for turbo frame loads to open the drawer
    this.element.addEventListener("turbo:frame-load", (event) => {
      if (event.target.id === "offcanvas_drawer") {
        this.applyVariant(this.pendingVariant || this.variantValue)
        this.open()
      }
    })
  }

  disconnect() {
    document.removeEventListener("click", this.handleTriggerClick)
    clearTimeout(this.closeTimeout)
    clearTimeout(this.completeTimeout)
  }

  handleTriggerClick(event) {
    const trigger = event.target.closest('[data-turbo-frame="offcanvas_drawer"]')
    if (!trigger) return

    this.pendingVariant = trigger.dataset.offcanvasVariant || this.variantValue
    setTimeout(() => window.dispatchEvent(new CustomEvent("dropdown:close-all")), 0)
  }

  open() {
    clearTimeout(this.closeTimeout)
    window.dispatchEvent(new CustomEvent("offcanvas:open"))
    this.element.classList.replace(this.closedClass, this.openClass)
    // Small delay to ensure display:block is applied before transition
    requestAnimationFrame(() => {
      this.panelTarget.classList.remove(this.closedTransformClass)
      this.panelTarget.classList.add(this.openTransformClass)
    })
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
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-slate-900"></div>
        </div>
      `
      document.body.classList.remove("overflow-hidden")
    }, 300)
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

    if (this.currentVariant === "fullscreen-bottom") {
      this.panelTarget.classList.add("inset-x-0", "bottom-0", "h-screen", "w-full", "translate-y-full")
    } else if (this.currentVariant === "compact-right") {
      this.panelTarget.classList.add("inset-y-0", "right-0", "w-full", "sm:w-[480px]", "md:w-[520px]", "lg:w-[560px]", "translate-x-full")
    } else {
      this.panelTarget.classList.add("inset-y-0", "right-0", "w-full", "sm:w-[600px]", "md:w-[800px]", "lg:w-[1000px]", "translate-x-full")
    }
  }

  get closedTransformClass() {
    return this.currentVariant === "fullscreen-bottom" ? "translate-y-full" : "translate-x-full"
  }

  get openTransformClass() {
    return this.currentVariant === "fullscreen-bottom" ? "translate-y-0" : "translate-x-0"
  }
}
