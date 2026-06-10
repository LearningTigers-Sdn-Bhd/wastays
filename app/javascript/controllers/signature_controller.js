import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

export default class extends Controller {
  static targets = ["canvas", "input"]

  connect() {
    this.signaturePad = new SignaturePad(this.canvasTarget, {
      backgroundColor: 'rgb(255, 255, 255)'
    })

    this.signaturePad.addEventListener("endStroke", () => {
      this.save()
    })

    window.addEventListener("resize", this.resizeCanvas.bind(this))
    this.resizeCanvas()
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeCanvas.bind(this))
  }

  resizeCanvas() {
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    this.canvasTarget.width = this.canvasTarget.offsetWidth * ratio
    this.canvasTarget.height = this.canvasTarget.offsetHeight * ratio
    this.canvasTarget.getContext("2d").scale(ratio, ratio)
    this.signaturePad.clear()
  }

  clear() {
    this.signaturePad.clear()
    this.inputTarget.value = ""
  }

  save() {
    if (this.signaturePad.isEmpty()) {
      this.inputTarget.value = ""
    } else {
      this.inputTarget.value = this.signaturePad.toDataURL()
    }
  }
}
