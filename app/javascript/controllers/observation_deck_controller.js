import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "frame"]

  open(event) {
    const entryId = event.currentTarget.dataset.entryId
    if (!entryId) return

    this.frameTarget.id = `entry_detail_${entryId}`
    this.frameTarget.src = `/admin/observation_deck/${entryId}`
    this.panelTarget.classList.remove("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }
}
