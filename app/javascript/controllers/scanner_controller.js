import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "canvas", "modal", "previewContainer", "captureButton", "retakeButton", "useButton"]
  static values = { inputId: String }

  connect() {
    this.stream = null
  }

  disconnect() {
    this.stopCamera()
    document.documentElement.classList.remove("scanner-active")
  }

  open(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    if (window.innerWidth < 768 && event.currentTarget.dataset.confirm && !confirm(event.currentTarget.dataset.confirm)) {
      return
    }
    
    this.currentInputId = event.currentTarget.dataset.inputId
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.classList.add("flex")
    document.documentElement.classList.add("scanner-active")
    
    // Reset any previous state
    this.resetUI()
    this.startCamera()
  }

  close(event) {
    if (event) event.preventDefault()
    this.stopCamera()
    this.modalTarget.classList.add("hidden")
    this.modalTarget.classList.remove("flex")
    document.documentElement.classList.remove("scanner-active")
    this.resetUI()
  }

  async startCamera() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } }
      })
      this.videoTarget.srcObject = this.stream
      this.videoTarget.onloadedmetadata = () => {
        this.videoTarget.play()
      }
    } catch (err) {
      console.error("Error accessing camera:", err)
      alert("Could not access camera. Please ensure you have granted permission and are using HTTPS.")
      this.close()
    }
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop())
      this.stream = null
    }
  }

  capture(event) {
    if (event) event.preventDefault()
    
    if (!this.videoTarget.videoWidth) {
      console.warn("Video not ready for capture")
      return
    }

    const context = this.canvasTarget.getContext("2d")
    this.canvasTarget.width = this.videoTarget.videoWidth
    this.canvasTarget.height = this.videoTarget.videoHeight
    
    context.drawImage(this.videoTarget, 0, 0, this.canvasTarget.width, this.canvasTarget.height)
    
    this.videoTarget.classList.add("hidden")
    this.canvasTarget.classList.remove("hidden")
    this.captureButtonTarget.classList.add("hidden")
    this.retakeButtonTarget.classList.remove("hidden")
    this.useButtonTarget.classList.remove("hidden")
  }

  retake(event) {
    if (event) event.preventDefault()
    this.resetUI()
    if (this.videoTarget.srcObject) {
      this.videoTarget.play()
    } else {
      this.startCamera()
    }
  }

  use(event) {
    if (event) event.preventDefault()
    
    this.canvasTarget.toBlob((blob) => {
      const file = new File([blob], `scan_${Date.now()}.jpg`, { type: "image/jpeg" })
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      
      const input = document.getElementById(this.currentInputId)
      if (input) {
        input.files = dataTransfer.files
        // Trigger the preview in the main upload controller
        input.dispatchEvent(new Event('change', { bubbles: true }))
      }
      
      this.close()
    }, "image/jpeg", 0.9)
  }

  resetUI() {
    this.videoTarget.classList.remove("hidden")
    this.canvasTarget.classList.add("hidden")
    this.captureButtonTarget.classList.remove("hidden")
    this.retakeButtonTarget.classList.add("hidden")
    this.useButtonTarget.classList.add("hidden")
  }
}
