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

    // Keep the bound reference so disconnect() removes this very listener.
    this.boundResizeCanvas = this.resizeCanvas.bind(this)
    window.addEventListener("resize", this.boundResizeCanvas)
    this.resizeCanvas()
  }

  disconnect() {
    window.removeEventListener("resize", this.boundResizeCanvas)
  }

  resizeCanvas() {
    // Resizing a canvas wipes its bitmap, so carry the strokes across it.
    // A resize mid-signature is routine on a tablet: the on-screen keyboard
    // opening or the address bar collapsing both fire it.
    const strokes = this.signaturePad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    this.canvasTarget.width = this.canvasTarget.offsetWidth * ratio
    this.canvasTarget.height = this.canvasTarget.offsetHeight * ratio
    this.canvasTarget.getContext("2d").scale(ratio, ratio)
    this.signaturePad.fromData(strokes)
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
      this.inputTarget.setCustomValidity("")
    }
  }
}
