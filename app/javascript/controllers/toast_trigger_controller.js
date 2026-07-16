import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    message: String,
    options: { type: Object, default: {} },
    viewportId: { type: String, default: "toast-viewport" }
  }

  connect() {
    this.show = this.show.bind(this)
    this.scheduleShow = this.scheduleShow.bind(this)
    document.addEventListener("toast:ready", this.scheduleShow)
    this.scheduleShow()
  }

  disconnect() {
    document.removeEventListener("toast:ready", this.scheduleShow)
    if (this.showFrame) cancelAnimationFrame(this.showFrame)
  }

  scheduleShow() {
    if (this.showFrame) cancelAnimationFrame(this.showFrame)
    this.showFrame = requestAnimationFrame(() => {
      this.showFrame = null
      this.show()
    })
  }

  show() {
    if (!this.messageValue) return this.element.remove()

    const viewport = document.getElementById(this.viewportIdValue)
    const controller = viewport && this.application.getControllerForElementAndIdentifier(viewport, "toast")
    if (!controller) return

    controller.showToast(this.messageValue, this.optionsValue)
    this.element.remove()
  }
}
