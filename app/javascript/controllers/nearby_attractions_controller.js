import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["more", "moreFooter", "remaining", "fewer", "fewerFooter"]

  expand() {
    this.moreFooterTarget.classList.add("hidden")
    this.moreTarget.setAttribute("aria-expanded", "true")
    this.remainingTarget.classList.remove("hidden")
    this.fewerFooterTarget.classList.remove("hidden")
    this.remainingTarget.querySelector("a")?.focus()
  }

  collapse() {
    this.remainingTarget.classList.add("hidden")
    this.fewerFooterTarget.classList.add("hidden")
    this.moreFooterTarget.classList.remove("hidden")
    this.moreTarget.setAttribute("aria-expanded", "false")
    this.moreTarget.focus()
  }
}
