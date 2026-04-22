import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "loading", "content"]

  start() {
    if (this.hasButtonTarget) this.buttonTarget.classList.add("hidden")
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
    this.loadingTarget.classList.remove("hidden")
  }
}
