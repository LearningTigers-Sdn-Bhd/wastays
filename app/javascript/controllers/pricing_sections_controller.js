import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "section" ]

  connect() {
    this.updateVisibility()
  }

  toggle(event) {
    this.updateVisibility()
  }

  updateVisibility() {
    const checkedTiers = Array.from(this.element.querySelectorAll('input[type="checkbox"][data-tier]'))
      .filter(cb => cb.checked)
      .map(cb => cb.dataset.tier)

    this.sectionTargets.forEach((section) => {
      const tier = section.dataset.tier
      section.classList.toggle("hidden", !checkedTiers.includes(tier))
    })
  }
}
