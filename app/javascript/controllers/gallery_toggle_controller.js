import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel", "grid", "viewer", 
    "lightboxImage", "backdropImage", "indexDisplay", "thumbnails",
    "backButton", "headerTitle", "viewerCounter"
  ]
  static values = {
    photos: Array,
    index: Number
  }

  show(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.remove("hidden")
    this.closeViewer() // Reset to grid view when opening
    document.body.classList.add("overflow-hidden")
  }

  hide(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  openViewer(event) {
    if (event) event.preventDefault()
    
    // Ensure the main panel is visible
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
    }

    const index = parseInt(event.currentTarget.dataset.index)
    this.indexValue = index
    
    this.renderThumbnails()
    this.showImage()
    
    if (this.hasGridTarget) this.gridTarget.classList.add("hidden")
    if (this.hasViewerTarget) this.viewerTarget.classList.remove("hidden")
    if (this.hasBackButtonTarget) this.backButtonTarget.classList.remove("hidden")
    if (this.hasViewerCounterTarget) this.viewerCounterTarget.classList.remove("hidden")
    if (this.hasHeaderTitleTarget) this.headerTitleTarget.textContent = "Back"
    
    // Scroll modal to top
    this.panelTarget.scrollTop = 0
  }

  closeViewer(event) {
    if (event) event.preventDefault()
    
    if (this.hasViewerTarget) this.viewerTarget.classList.add("hidden")
    if (this.hasGridTarget) this.gridTarget.classList.remove("hidden")
    if (this.hasBackButtonTarget) this.backButtonTarget.classList.add("hidden")
    if (this.hasViewerCounterTarget) this.viewerCounterTarget.classList.add("hidden")
    if (this.hasHeaderTitleTarget) this.headerTitleTarget.textContent = "Hotel Photos"
  }

  next(event) {
    if (event) event.preventDefault()
    if (!this.photosValue || this.photosValue.length === 0) return
    this.indexValue = (this.indexValue + 1) % this.photosValue.length
    this.showImage()
  }

  prev(event) {
    if (event) event.preventDefault()
    if (!this.photosValue || this.photosValue.length === 0) return
    this.indexValue = (this.indexValue - 1 + this.photosValue.length) % this.photosValue.length
    this.showImage()
  }

  switchImage(event) {
    if (event) event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    this.indexValue = index
    this.showImage()
  }

  showImage() {
    if (!this.photosValue || this.photosValue.length === 0) return
    const currentPhoto = this.photosValue[this.indexValue]
    
    if (this.hasLightboxImageTarget) {
      this.lightboxImageTarget.src = currentPhoto
    }
    
    if (this.hasBackdropImageTarget) {
      this.backdropImageTarget.src = currentPhoto
    }

    if (this.hasIndexDisplayTarget) {
      this.indexDisplayTarget.textContent = this.indexValue + 1
    }

    this.updateThumbnailBorders()
  }

  renderThumbnails() {
    if (!this.hasThumbnailsTarget) return
    this.thumbnailsTarget.innerHTML = ""
    
    this.photosValue.forEach((photo, index) => {
      const thumb = document.createElement("img")
      thumb.src = photo
      thumb.className = "h-12 w-16 md:h-16 md:w-20 shrink-0 rounded-lg object-cover cursor-pointer border-2 transition-all border-transparent opacity-50 hover:opacity-100 hover:border-white/40"
      thumb.dataset.action = "click->gallery-toggle#switchImage"
      thumb.dataset.index = index
      this.thumbnailsTarget.appendChild(thumb)
    })
  }

  updateThumbnailBorders() {
    if (!this.hasThumbnailsTarget) return
    
    const thumbs = this.thumbnailsTarget.querySelectorAll("img")
    thumbs.forEach((img, idx) => {
      if (idx === this.indexValue) {
        img.classList.remove("border-transparent", "opacity-50")
        img.classList.add("border-white", "opacity-100", "scale-110")
        img.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
      } else {
        img.classList.add("border-transparent", "opacity-50")
        img.classList.remove("border-white", "opacity-100", "scale-110")
      }
    })
  }

  // Touch Support for Mobile
  touchStart(event) {
    if (!event.touches || event.touches.length === 0) return
    this.touchStartX = event.touches[0].clientX
    this.touchCurrentX = this.touchStartX
  }

  touchMove(event) {
    if (!event.touches || event.touches.length === 0) return
    this.touchCurrentX = event.touches[0].clientX
  }

  touchEnd() {
    if (this.touchStartX === null || this.touchCurrentX === null) return

    const distance = this.touchCurrentX - this.touchStartX
    const swipeThreshold = 50

    if (Math.abs(distance) >= swipeThreshold) {
      if (distance < 0) {
        this.next()
      } else {
        this.prev()
      }
    }

    this.touchStartX = null
    this.touchCurrentX = null
  }

  stop(event) {
    event.stopPropagation()
  }
}
