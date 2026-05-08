import { Controller } from "@hotwired/stimulus"
import { computePosition, flip, shift, offset, autoUpdate } from "@floating-ui/dom"

export default class extends Controller {
  static targets = ["reference", "floating"]
  static values = {
    placement: { type: String, default: "bottom" },
    offset: { type: Number, default: 8 },
    open: { type: Boolean, default: false },
    trigger: { type: String, default: "click" },
    portal: { type: Boolean, default: true }
  }

  connect() {
    if (this.triggerValue === "hover") {
      this.boundShow = this.show.bind(this)
      this.boundHide = this.hide.bind(this)
      this.referenceTarget.addEventListener("mouseenter", this.boundShow)
      this.referenceTarget.addEventListener("mouseleave", this.boundHide)
    }

    if (this.openValue) {
      this.show()
    }
  }

  disconnect() {
    this.hide()
    if (this.triggerValue === "hover") {
      this.referenceTarget.removeEventListener("mouseenter", this.boundShow)
      this.referenceTarget.removeEventListener("mouseleave", this.boundHide)
    }
    
    // If we portaled it, we should probably remove it if the controller is being destroyed
    if (this.hasFloatingTarget && this.portalValue && this.floatingTarget.parentElement === document.body) {
      this.floatingTarget.remove()
    }
  }

  toggle(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    
    if (this.openValue) {
      this.hide()
    } else {
      this.show()
    }
  }

  show() {
    if (this.openValue && this.triggerValue === "click") return

    // Safely get the floating element. Once portaled, this.floatingTarget will fail.
    if (!this.floatingElement) {
      if (this.hasFloatingTarget) {
        this.floatingElement = this.floatingTarget
      } else {
        return
      }
    }

    this.openValue = true
    
    // Portalling logic: move to body to avoid clipping
    if (this.portalValue && this.floatingElement.parentElement !== document.body) {
      document.body.appendChild(this.floatingElement)
    }

    this.floatingElement.classList.remove("hidden")
    this.floatingElement.style.display = "block"
    
    this.cleanup = autoUpdate(
      this.referenceTarget,
      this.floatingElement,
      () => this.updatePosition(),
      { animationFrame: true }
    )

    if (this.triggerValue === "click") {
      this.clickOutsideHandler = (event) => {
        if (!this.element.contains(event.target) && !this.floatingElement.contains(event.target)) {
          this.hide()
        }
      }
      document.addEventListener("click", this.clickOutsideHandler)
    }
  }

  hide() {
    if (!this.openValue) return
    if (!this.floatingElement) return

    this.openValue = false
    this.floatingElement.classList.add("hidden")
    this.floatingElement.style.display = "none"
    
    if (this.cleanup) {
      this.cleanup()
      this.cleanup = null
    }

    if (this.clickOutsideHandler) {
      document.removeEventListener("click", this.clickOutsideHandler)
      this.clickOutsideHandler = null
    }
  }

  updatePosition() {
    if (!this.hasReferenceTarget || !this.floatingElement) return

    computePosition(this.referenceTarget, this.floatingElement, {
      placement: this.placementValue,
      strategy: 'fixed',
      middleware: [
        offset(this.offsetValue),
        flip(),
        shift({ padding: 5 })
      ],
    }).then(({ x, y }) => {
      Object.assign(this.floatingElement.style, {
        left: `${x}px`,
        top: `${y}px`,
        position: 'fixed',
        zIndex: '9999',
        width: 'max-content',
        right: 'auto',
        bottom: 'auto'
      })
    })
  }
}
