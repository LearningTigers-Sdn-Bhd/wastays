import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    message: String,
    options: { type: Object, default: {} },
    viewportId: { type: String, default: "toast-viewport" }
  }

  connect() {
    this.show = this.show.bind(this)
    document.addEventListener("toast:ready", this.show)
    this.show()
  }

  disconnect() {
    document.removeEventListener("toast:ready", this.show)
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
