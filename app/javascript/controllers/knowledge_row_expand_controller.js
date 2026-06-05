import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["expandable", "chevron"]

  toggle(event) {
    if (event.target.closest("a, button, [data-controller='dropdown']")) {
      return
    }
    this.expandableTarget.classList.toggle("hidden")
    this.element.classList.toggle("is-expanded")
    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("rotate-180")
    }
  }
}
