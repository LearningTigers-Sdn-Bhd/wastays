import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "container", "field"]

  connect() {
    this.toggle()
  }

  toggle() {
    const enabled = this.checkboxTarget.checked

    this.fieldTargets.forEach((field) => {
      const controls = field.matches("input, select, textarea, button") ? [field] : field.querySelectorAll("input, select, textarea, button")
      controls.forEach((control) => { control.disabled = !enabled })
    })

    this.containerTargets.forEach((container) => {
      container.classList.toggle("opacity-50", !enabled)
    })
  }
}
