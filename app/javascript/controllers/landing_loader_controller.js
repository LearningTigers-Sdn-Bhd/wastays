import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]
  static values = {
    delay: { type: Number, default: 820 }
  }

  connect() {
    this.handleBeforeCache = this.reset.bind(this)
    this.handleBeforeRender = this.releaseScrollLock.bind(this)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
    document.addEventListener("turbo:before-render", this.handleBeforeRender)

    this.reset()
    this.dismissWhenReady()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    document.removeEventListener("turbo:before-render", this.handleBeforeRender)
    this.clearTimers()
    this.releaseScrollLock()
  }

  dismissWhenReady() {
    const finish = () => {
      this.clearTimers()
      this.dismissTimer = window.setTimeout(() => this.dismiss(), this.delayValue)
    }

    if (document.readyState === "complete") {
      finish()
      return
    }

    this.loadHandler = () => finish()
    window.addEventListener("load", this.loadHandler, { once: true })

    this.fallbackTimer = window.setTimeout(() => {
      if (this.loadHandler) {
        window.removeEventListener("load", this.loadHandler)
        this.loadHandler = null
      }
      finish()
    }, 1400)
  }

  dismiss() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.add("is-hidden")
    this.releaseScrollLock()
  }

  reset() {
    if (!this.hasOverlayTarget) return

    this.clearTimers()
    this.overlayTarget.classList.remove("is-hidden")
    document.documentElement.classList.add("landing-loader-active")
  }

  releaseScrollLock() {
    document.documentElement.classList.remove("landing-loader-active")
  }

  clearTimers() {
    if (this.dismissTimer) {
      window.clearTimeout(this.dismissTimer)
      this.dismissTimer = null
    }

    if (this.fallbackTimer) {
      window.clearTimeout(this.fallbackTimer)
      this.fallbackTimer = null
    }

    if (this.loadHandler) {
      window.removeEventListener("load", this.loadHandler)
      this.loadHandler = null
    }
  }
}
