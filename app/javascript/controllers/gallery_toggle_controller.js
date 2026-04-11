import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "lightbox", "lightboxImage", "indexDisplay"]
  static values = {
    photos: Array,
    index: Number
  }

  show(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  hide(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.add("hidden")
    this.closeLightbox()
    document.body.classList.remove("overflow-hidden")
  }

  openLightbox(event) {
    if (event) event.preventDefault()
    if (window.innerWidth >= 768) return

    const index = parseInt(event.currentTarget.dataset.index)
    this.indexValue = index
    this.showImage()
    this.lightboxTarget.classList.remove("hidden")
  }

  closeLightbox(event) {
    if (event) event.preventDefault()
    this.lightboxTarget.classList.add("hidden")
  }

  next(event) {
    if (event) event.preventDefault()
    this.indexValue = (this.indexValue + 1) % this.photosValue.length
    this.showImage()
  }

  prev(event) {
    if (event) event.preventDefault()
    this.indexValue = (this.indexValue - 1 + this.photosValue.length) % this.photosValue.length
    this.showImage()
  }

  showImage() {
    if (this.hasLightboxImageTarget) {
      this.lightboxImageTarget.src = this.photosValue[this.indexValue]
    }
    if (this.hasIndexDisplayTarget) {
      this.indexDisplayTarget.textContent = this.indexValue + 1
    }
  }

  stop(event) {
    event.stopPropagation()
  }
}
