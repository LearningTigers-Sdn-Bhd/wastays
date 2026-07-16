import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image"]

  connect() {
    if (this.hasImageTarget && this.imageTarget.complete && this.imageTarget.naturalWidth === 0) {
      this.hideFailedImage()
    }
  }

  hideFailedImage() {
    if (!this.hasImageTarget) return

    this.imageTarget.hidden = true
    this.element.dataset.imageState = "error"
  }
}
