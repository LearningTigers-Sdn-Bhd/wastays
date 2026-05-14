import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "placeholder"]

  openGallery(event) {
    event.preventDefault()
    this.inputTarget.removeAttribute("capture")
    this.inputTarget.click()
  }

  openCamera(event) {
    event.preventDefault()
    this.inputTarget.setAttribute("capture", "environment")
    this.inputTarget.click()
  }

  updatePreview(event) {
    const file = event.target.files[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = (e) => {
        this.previewTarget.src = e.target.result
        this.previewTarget.classList.remove("hidden")
        this.placeholderTarget.classList.add("hidden")
      }
      reader.readAsDataURL(file)
    }
  }
}
