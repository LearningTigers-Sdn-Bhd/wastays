import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const TONES = ["default", "info", "warning", "success", "destructive"]
const ACTION_VARIANTS = {
  default: "primary",
  info: "info",
  warning: "warning",
  success: "success",
  destructive: "destructive",
}

// Installs a native AlertDialog as Turbo's asynchronous form confirmation host.
// The dialog lifecycle itself remains owned by panels-ui--dialog; this controller
// only maps Turbo metadata into the surface and settles Turbo's pending promise.
export default class extends Controller {
  connect() {
    this.titleElement = this.element.querySelector('[data-slot="alert-dialog-title"]')
    this.descriptionElement = this.element.querySelector('[data-slot="alert-dialog-description"]')
    this.cancelButton = this.element.querySelector('[data-slot="alert-dialog-cancel"]')
    this.actionButton = this.element.querySelector('[data-slot="alert-dialog-action"]')
    this.pendingResolve = null

    this.previousConfirm = Turbo.config.forms.confirm
    this.confirmHandler = (message, source) => this.open(message, source)
    Turbo.config.forms.confirm = this.confirmHandler
  }

  disconnect() {
    this.settle(false)
    if (Turbo.config.forms.confirm === this.confirmHandler) {
      Turbo.config.forms.confirm = this.previousConfirm
    }
  }

  open(message, source) {
    this.settle(false)
    if (this.element.open) this.element.close()

    const content = this.contentFor(message, source)
    this.titleElement.textContent = content.title
    this.descriptionElement.textContent = content.description
    this.applyTone(content.tone)

    const promise = new Promise((resolve) => {
      this.pendingResolve = resolve
    })
    this.element.showModal()
    return promise
  }

  confirm() {
    this.settle(true)
  }

  cancel() {
    this.settle(false)
  }

  closed() {
    this.settle(false)
  }

  settle(result) {
    if (!this.pendingResolve) return

    const resolve = this.pendingResolve
    this.pendingResolve = null
    resolve(result)
  }

  contentFor(message, source) {
    const detailedMessage = source?.dataset?.turboConfirmText
    const explicitTitle = source?.dataset?.turboConfirmTitle

    return {
      title: explicitTitle || (detailedMessage ? message : "Confirm action"),
      description: detailedMessage || message,
      tone: this.toneFor(source),
    }
  }

  toneFor(source) {
    const explicitTone = source?.dataset?.turboConfirmTone
    if (TONES.includes(explicitTone)) return explicitTone

    switch (source?.dataset?.turboConfirmColor) {
      case "red": return "destructive"
      case "green": return "success"
      default: return "default"
    }
  }

  applyTone(tone) {
    this.element.dataset.tone = tone
    this.actionButton.dataset.variant = ACTION_VARIANTS[tone]
    this.cancelButton.dataset.variant = tone === "default" ? "neutral" : "ghost"
  }
}
