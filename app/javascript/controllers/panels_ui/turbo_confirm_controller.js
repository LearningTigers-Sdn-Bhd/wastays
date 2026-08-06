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
    this.confirmHandler = (message, form, submitter) => this.open(message, form, submitter)
    Turbo.config.forms.confirm = this.confirmHandler
  }

  disconnect() {
    this.settle(false)
    if (Turbo.config.forms.confirm === this.confirmHandler) {
      Turbo.config.forms.confirm = this.previousConfirm
    }
  }

  open(message, form, submitter) {
    this.settle(false)
    if (this.element.open) this.element.close()

    const content = this.contentFor(message, form, submitter)
    this.titleElement.textContent = content.title
    this.descriptionElement.textContent = content.description
    this.applyTone(content.tone)

    const promise = new Promise((resolve) => {
      this.pendingResolve = resolve
      this.pendingForm = form
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
    // Native close events are queued. If a confirmation is reopened before the
    // previous event is delivered, that stale event must not cancel the new
    // pending promise.
    if (this.element.open) return

    this.settle(false)
  }

  settle(result) {
    if (!this.pendingResolve) return

    const resolve = this.pendingResolve
    const form = this.pendingForm
    this.pendingResolve = null
    this.pendingForm = null
    resolve(result)

    // A declined confirm never reaches turbo:submit-start, so a control that
    // already moved (a switch, a checkbox) has no other signal telling it to go
    // back. Announce the outcome on the form either way and let it decide.
    form?.dispatchEvent(
      new CustomEvent("panels-ui:confirm-settled", {
        bubbles: true,
        detail: { confirmed: result },
      })
    )
  }

  contentFor(message, form, submitter) {
    const detailedMessage = this.metadataValue("turboConfirmText", submitter, form)
    const explicitTitle = this.metadataValue("turboConfirmTitle", submitter, form)

    return {
      title: explicitTitle || (detailedMessage ? message : "Confirm action"),
      description: detailedMessage || message,
      tone: this.toneFor(form, submitter),
    }
  }

  toneFor(form, submitter) {
    const explicitTone = this.metadataValue("turboConfirmTone", submitter, form)
    if (TONES.includes(explicitTone)) return explicitTone

    switch (this.metadataValue("turboConfirmColor", submitter, form)) {
      case "red": return "destructive"
      case "green": return "success"
      default: return "default"
    }
  }

  metadataValue(key, ...sources) {
    for (const source of sources) {
      const value = source?.dataset?.[key]
      if (value !== undefined) return value
    }
  }

  applyTone(tone) {
    this.element.dataset.tone = tone
    this.actionButton.dataset.variant = ACTION_VARIANTS[tone]
    this.cancelButton.dataset.variant = tone === "default" ? "neutral" : "ghost"
  }
}
