import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "chevron"]

  toggle(event) {
    const section = event.params.section
    const expanded = event.currentTarget.getAttribute("aria-expanded") === "true"

    event.currentTarget.setAttribute("aria-expanded", String(!expanded))

    this.rowTargets
      .filter((row) => row.dataset.section === section)
      .forEach((row) => row.classList.toggle("hidden", expanded))

    const chevron = this.chevronTargets.find((icon) => icon.dataset.section === section)
    if (chevron) chevron.textContent = expanded ? "▸" : "▾"
  }
}
