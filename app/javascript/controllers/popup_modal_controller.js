import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame"]
  static values = { url: String }

  open(event) {
    if (event) event.preventDefault()
    
    // Get URL from the clicked element's data attribute or the controller's value
    const url = event?.currentTarget?.dataset?.popupModalUrlValue || this.urlValue

    // Load frame source if provided
    if (this.hasFrameTarget && url) {
      const targetUrl = new URL(url, window.location.origin).href
      if (this.frameTarget.src !== targetUrl) {
        this.frameTarget.src = url
      }
    }

    // Show modal
    this.dialogTarget.classList.remove("hidden")
    this.dialogTarget.classList.add("flex")
    document.body.classList.add("overflow-hidden")

    // Trigger animation
    requestAnimationFrame(() => {
      const content = this.dialogTarget.querySelector(".modal-content")
      if (content) {
        content.classList.remove("opacity-0", "translate-y-4", "sm:scale-95")
        content.classList.add("opacity-100", "translate-y-0", "sm:scale-100")
      }
    })
  }

  close(event) {
    const content = this.dialogTarget.querySelector(".modal-content")
    if (content) {
      content.classList.add("opacity-0", "translate-y-4", "sm:scale-95")
      content.classList.remove("opacity-100", "translate-y-0", "sm:scale-100")
    }

    // Wait for animation
    setTimeout(() => {
      this.dialogTarget.classList.add("hidden")
      this.dialogTarget.classList.remove("flex")
      document.body.classList.remove("overflow-hidden")
    }, 200)
  }

  // Close on background click
  handleBackgroundClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
