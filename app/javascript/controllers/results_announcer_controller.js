import { Controller } from "@hotwired/stimulus"

// Announces how many results a turbo frame came back with.
//
// The live region has to outlive the swap to be announced at all, so it sits
// outside the frame and this controller copies the frame's summary into it on
// every frame load. Announcing the frame itself would read the whole table.
export default class extends Controller {
  static targets = ["status"]

  connect() {
    this.announceBound = this.announce.bind(this)
    this.element.addEventListener("turbo:frame-load", this.announceBound)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.announceBound)
  }

  announce(event) {
    if (!this.hasStatusTarget) return

    const summary = event.target.querySelector("[data-board-summary]")
    if (summary) this.statusTarget.textContent = summary.textContent.trim()
  }
}
