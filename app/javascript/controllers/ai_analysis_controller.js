import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "loading", "content"]

  start() {
    if (this.hasButtonTarget) this.buttonTarget.hidden = true
    if (this.hasContentTarget) this.contentTarget.hidden = true
    if (this.hasLoadingTarget) this.loadingTarget.hidden = false
  }
}
