import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "previewContainer", "choiceMenu"]

  openGallery(event) {
    if (this.previewContainerTarget.classList.contains("hidden")) {
      this._openGallery(event)
    } else {
      if (this.isMobile) {
        this.openChoiceMenu(event)
      } else {
        this._openGallery(event)
      }
    }
  }

  openChoiceMenu(event) {
    if (event) event.preventDefault()
    this.choiceMenuTarget.classList.remove("hidden")
    document.documentElement.classList.add("scanner-active")
    // Use a small timeout to allow display:block to hit the DOM before animating
    setTimeout(() => {
      this.choiceMenuTarget.querySelector(".translate-y-full")?.classList.remove("translate-y-full")
    }, 10)
  }

  closeChoiceMenu(event) {
    if (event) event.preventDefault()
    const content = this.choiceMenuTarget.querySelector(".bg-white")
    if (content) {
      content.classList.add("translate-y-full")
    }
    
    // Use a small timeout to let the scanner controller open first if it's going to
    setTimeout(() => {
      const scannerModal = document.querySelector('[data-scanner-target="modal"]')
      const isScannerOpen = scannerModal && !scannerModal.classList.contains("hidden")
      
      if (!isScannerOpen) {
        document.documentElement.classList.remove("scanner-active")
      }
    }, 100)

    setTimeout(() => {
      this.choiceMenuTarget.classList.add("hidden")
    }, 300)
  }

  _openGallery(event) {
    if (event) event.preventDefault()
    this.closeChoiceMenu()
    this.inputTarget.removeAttribute("capture")
    this.inputTarget.click()
  }

  openCamera(event) {
    if (this.previewContainerTarget.classList.contains("hidden")) {
      this._openCamera(event)
    } else {
      if (this.isMobile) {
        this.openChoiceMenu(event)
      } else {
        this._openCamera(event)
      }
    }
  }

  _openCamera(event) {
    if (event) event.preventDefault()
    this.closeChoiceMenu()
    this.inputTarget.setAttribute("capture", "environment")
    this.inputTarget.click()
  }

  updatePreview(event) {
    const file = event.target.files[0]
    if (file) {
      this.lastFile = file // Backup the file
      const reader = new FileReader()
      reader.onload = (e) => {
        this.previewTarget.src = e.target.result
        this.previewContainerTarget.classList.remove("hidden")
        this.placeholderTarget.classList.add("hidden")
      }
      reader.readAsDataURL(file)
    } else if (this.lastFile) {
      // If the input was cleared (e.g. user clicked 'Cancel' in browser picker)
      // but we have a backup, restore it!
      this.restoreBackup()
    }
  }

  restoreBackup() {
    if (!this.lastFile) return
    
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(this.lastFile)
    this.inputTarget.files = dataTransfer.files
  }

  reset(event) {
    if (event) event.preventDefault()
    if (this.isMobile) {
      if (confirm("Do you want to remove this photo and retake it?")) {
        this._reset()
      }
    } else {
      this._reset()
    }
  }

  _reset() {
    this.inputTarget.value = ""
    this.previewContainerTarget.classList.add("hidden")
    this.placeholderTarget.classList.remove("hidden")
  }

  get isMobile() {
    return window.innerWidth < 768
  }
}
