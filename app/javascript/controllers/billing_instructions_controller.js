import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["childRow", "chevron"]

  toggle(event) {
    if (event.target.closest("a, form, [data-billing-instructions-ignore]")) return

    const key = event.params.key
    const expanded = event.currentTarget.getAttribute("aria-expanded") === "true"

    this.setExpanded(key, !expanded)
  }

  buttonToggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const key = event.params.key
    const parentRow = this.element.querySelector(`[data-billing-instructions-row-key="${key}"]`)
    const expanded = parentRow?.getAttribute("aria-expanded") === "true"

    this.setExpanded(key, !expanded)
  }

  setExpanded(key, expanded) {
    const parentRow = this.element.querySelector(`[data-billing-instructions-row-key="${key}"]`)
    parentRow?.setAttribute("aria-expanded", String(expanded))

    this.childRowTargets
      .filter((row) => row.dataset.billingInstructionsKey === key)
      .forEach((row) => row.classList.toggle("hidden", !expanded))

    this.chevronTargets
      .filter((icon) => icon.dataset.billingInstructionsKey === key)
      .forEach((icon) => icon.classList.toggle("rotate-90", expanded))
  }
}
