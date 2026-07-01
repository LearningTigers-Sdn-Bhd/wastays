import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "uploadSection", "frontContainer", "backContainer"]
  static values = { isConcierge: { type: Boolean, default: false } }

  connect() {
    this.toggleUploads(true)
  }

  toggleUploads(immediate = false) {
    const docType = this.selectTarget.value

    if (docType === "ic") {
      this.showSection(this.uploadSectionTarget, immediate)
      this.showElement(this.frontContainerTarget, immediate)
      this.showElement(this.backContainerTarget, immediate)

      this.updateLabel(this.frontContainerTarget, "Front ID Card")
      this.updateLabel(this.backContainerTarget, "Back ID Card")
      this.toggleInput(this.frontContainerTarget, false)
      this.toggleInput(this.backContainerTarget, false)
      this.setICLayout()

    } else if (docType === "passport") {
      this.showSection(this.uploadSectionTarget, immediate)
      this.showElement(this.frontContainerTarget, immediate)
      this.hideElement(this.backContainerTarget, immediate)

      this.updateLabel(this.frontContainerTarget, "Passport Photo Page")
      this.toggleInput(this.frontContainerTarget, false)
      this.toggleInput(this.backContainerTarget, true)
      this.setPassportLayout()

    } else {
      // Empty or select prompt
      this.hideSection(this.uploadSectionTarget, immediate)
      this.toggleInput(this.frontContainerTarget, true)
      this.toggleInput(this.backContainerTarget, true)
    }
  }

  setICLayout() {
    if (this.isMobile) return

    const container = this.frontContainerTarget
    container.classList.remove("md:col-span-2", "w-full")

    const heightWrapper = container.querySelector(".group")
    if (heightWrapper) {
      heightWrapper.classList.remove("md:h-64", "md:max-w-[600px]", "md:max-w-[480px]")
      heightWrapper.classList.add("h-44")
    }
  }

  setPassportLayout() {
    if (this.isMobile) return

    const container = this.frontContainerTarget
    container.classList.add("md:col-span-2", "w-full")

    const heightWrapper = container.querySelector(".group")
    if (heightWrapper) {
      heightWrapper.classList.remove("h-44")
      if (this.isConciergeValue) {
        heightWrapper.classList.add("md:h-64", "md:max-w-[600px]")
      } else {
        heightWrapper.classList.add("md:h-64", "md:max-w-[480px]")
      }
    }
  }

  get isMobile() {
    return window.innerWidth < 768
  }

  showSection(el, immediate) {
    if (immediate) {
      el.classList.remove("hidden")
      el.classList.remove("opacity-0", "scale-95", "-translate-y-2")
      el.classList.add("opacity-100", "scale-100", "translate-y-0")
    } else {
      if (el.classList.contains("hidden")) {
        el.classList.remove("hidden")
        // Force reflow
        el.offsetHeight
        el.classList.remove("opacity-0", "scale-95", "-translate-y-2")
        el.classList.add("opacity-100", "scale-100", "translate-y-0")
      }
    }
  }

  hideSection(el, immediate) {
    if (immediate) {
      el.classList.add("hidden")
      el.classList.remove("opacity-100", "scale-100", "translate-y-0")
      el.classList.add("opacity-0", "scale-95", "-translate-y-2")
    } else {
      if (!el.classList.contains("hidden")) {
        el.classList.remove("opacity-100", "scale-100", "translate-y-0")
        el.classList.add("opacity-0", "scale-95", "-translate-y-2")
        el.addEventListener("transitionend", () => {
          if (el.classList.contains("opacity-0")) {
            el.classList.add("hidden")
          }
        }, { once: true })
      }
    }
  }

  showElement(el, immediate) {
    if (immediate) {
      el.classList.remove("hidden")
      el.classList.remove("opacity-0", "scale-95", "-translate-y-2")
      el.classList.add("opacity-100", "scale-100", "translate-y-0")
    } else {
      if (el.classList.contains("hidden")) {
        el.classList.remove("hidden")
        // Force reflow
        el.offsetHeight
        el.classList.remove("opacity-0", "scale-95", "-translate-y-2")
        el.classList.add("opacity-100", "scale-100", "translate-y-0")
      }
    }
  }

  hideElement(el, immediate) {
    if (immediate) {
      el.classList.add("hidden")
      el.classList.remove("opacity-100", "scale-100", "translate-y-0")
      el.classList.add("opacity-0", "scale-95", "-translate-y-2")
    } else {
      if (!el.classList.contains("hidden")) {
        el.classList.remove("opacity-100", "scale-100", "translate-y-0")
        el.classList.add("opacity-0", "scale-95", "-translate-y-2")
        el.addEventListener("transitionend", () => {
          if (el.classList.contains("opacity-0")) {
            el.classList.add("hidden")
          }
        }, { once: true })
      }
    }
  }

  updateLabel(container, text) {
    const label = container.querySelector("label")
    if (label) {
      label.textContent = text
    }
  }

  toggleInput(container, isDisabled) {
    const input = container.querySelector("input[type='file']")
    if (input) {
      input.disabled = isDisabled
    }
  }
}
