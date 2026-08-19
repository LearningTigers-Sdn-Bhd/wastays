import { Controller } from "@hotwired/stimulus"

// Keeps the newest message in view. A chat that opens at the top of a long
// thread makes the guest scroll to find the answer they just asked for.
export default class extends Controller {
  static targets = ["log", "input"]

  connect() {
    this.scrollToLatest()
  }

  scrollToLatest() {
    if (!this.hasLogTarget) return

    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }
}
