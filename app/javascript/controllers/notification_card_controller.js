import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "content"]
  static classes = ["active", "inactive"]

  connect() {
    this.refresh()
  }

  refresh() {
    const isEnabled = this.toggleTarget.checked
    this.element.classList.toggle("is-disabled", !isEnabled)
    
    // Toggle card visual state
    if (isEnabled) {
      this.element.classList.remove(...this.inactiveClasses)
      this.element.classList.add(...this.activeClasses)
      this.contentTarget.classList.remove("opacity-40", "grayscale", "pointer-events-none")
      this.element.classList.remove("border-slate-100")
      this.element.classList.add("border-slate-200")
    } else {
      this.element.classList.remove(...this.activeClasses)
      this.element.classList.add(...this.inactiveClasses)
      this.contentTarget.classList.add("opacity-40", "grayscale", "pointer-events-none")
      this.element.classList.remove("border-slate-200")
      this.element.classList.add("border-slate-100")
    }

    // Disable/Enable all inputs within the content area
    const inputs = this.contentTarget.querySelectorAll("input, select, textarea, button")
    inputs.forEach(input => {
      if (input.type !== "hidden") {
        input.disabled = !isEnabled
      }
    })
  }
}
