import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "loading", "content"]

  start() {
    this.buttonTarget.classList.add("hidden")
    this.loadingTarget.classList.remove("hidden")
  }
}
