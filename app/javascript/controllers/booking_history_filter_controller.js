import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["event", "filter", "filteredCount", "filteredEmpty"]

  filter(event) {
    const category = event.currentTarget.dataset.category
    let visibleCount = 0

    this.filterTargets.forEach((button) => {
      const active = button.dataset.category === category
      button.dataset.active = active
      button.setAttribute("aria-pressed", active)
    })

    this.eventTargets.forEach((row) => {
      const visible = category === "all" || row.dataset.category === category
      row.classList.toggle("hidden", !visible)
      if (visible) visibleCount += 1
    })

    this.filteredCountTarget.textContent = visibleCount
    this.filteredEmptyTarget.classList.toggle("hidden", visibleCount > 0)
  }
}
