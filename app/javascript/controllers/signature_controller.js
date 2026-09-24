import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

export default class extends Controller {
  static targets = ["canvas", "input", "clearButton", "overlay", "expandedCanvas"]

  connect() {
    this.signaturePad = this.buildPad(this.canvasTarget)

    this.signaturePad.addEventListener("endStroke", () => {
      this.save()
      this.toggleClearButton()
    })

    // Keep the bound reference so disconnect() removes this very listener.
    this.boundResizeCanvas = this.resizeCanvas.bind(this)
    window.addEventListener("resize", this.boundResizeCanvas)
    this.resizeCanvas()
  }

  disconnect() {
    window.removeEventListener("resize", this.boundResizeCanvas)
  }

  buildPad(canvas) {
    return new SignaturePad(canvas, { backgroundColor: "rgb(255, 255, 255)" })
  }

  resizeCanvas() {
    this.resizePad(this.canvasTarget, this.signaturePad)

    if (this.expandedPad && this.overlayOpen) {
      this.resizePad(this.expandedCanvasTarget, this.expandedPad)
    }
  }

  // Resizing a canvas wipes its bitmap, so carry the strokes across it. A
  // resize mid-signature is routine on a tablet: the on-screen keyboard
  // opening or the address bar collapsing both fire it.
  resizePad(canvas, pad) {
    const strokes = pad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    canvas.width = canvas.offsetWidth * ratio
    canvas.height = canvas.offsetHeight * ratio
    canvas.getContext("2d").scale(ratio, ratio)
    pad.fromData(strokes)
  }

  clear() {
    this.signaturePad.clear()
    this.inputTarget.value = ""
    this.toggleClearButton()
  }

  toggleClearButton() {
    if (!this.hasClearButtonTarget) return

    this.clearButtonTarget.classList.toggle("hidden", this.signaturePad.isEmpty())
  }

  save() {
    if (this.signaturePad.isEmpty()) {
      this.inputTarget.value = ""
    } else {
      this.inputTarget.value = this.signaturePad.toDataURL()
      this.inputTarget.setCustomValidity("")
    }
  }

  // A signature box that fits under the stay details is too small to sign
  // comfortably on a phone. This opens the same signature full-screen instead
  // of replacing it, so switching back and forth never loses a stroke.
  expand() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.overlayOpen = true

    if (!this.expandedPad) {
      this.expandedPad = this.buildPad(this.expandedCanvasTarget)
    }

    // The canvas has to be laid out (not display:none) before its real size
    // can be read, which is what the resize and the coordinate scaling below
    // both depend on.
    requestAnimationFrame(() => {
      this.resizePad(this.expandedCanvasTarget, this.expandedPad)
      this.expandedPad.fromData(
        this.scalePoints(this.signaturePad.toData(), this.canvasTarget, this.expandedCanvasTarget)
      )
    })
  }

  collapse() {
    if (!this.hasOverlayTarget) return

    if (this.expandedPad) {
      const scaled = this.scalePoints(this.expandedPad.toData(), this.expandedCanvasTarget, this.canvasTarget)
      this.signaturePad.fromData(scaled)
    }

    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    this.overlayOpen = false
    this.save()
    this.toggleClearButton()
  }

  clearExpanded() {
    if (this.expandedPad) this.expandedPad.clear()
  }

  // signature_pad records points in the canvas's own CSS pixel space, so
  // moving strokes onto a canvas of a different size has to scale each point
  // by how much bigger or smaller the destination is -- otherwise a signature
  // drawn across a full-screen canvas lands clipped in a corner of the small
  // one, or vice versa.
  scalePoints(strokes, fromCanvas, toCanvas) {
    const scaleX = toCanvas.offsetWidth / fromCanvas.offsetWidth || 1
    const scaleY = toCanvas.offsetHeight / fromCanvas.offsetHeight || 1

    return strokes.map((stroke) => ({
      ...stroke,
      points: stroke.points.map((point) => ({ ...point, x: point.x * scaleX, y: point.y * scaleY }))
    }))
  }
}
