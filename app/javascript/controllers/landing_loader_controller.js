import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]
  static values = {
    delay: { type: Number, default: 820 }
  }

  connect() {
    if (sessionStorage.getItem("landing_loader_shown")) {
      this.element.remove()
      return
    }

    this.handleBeforeCache = this.prepareForCache.bind(this)
    this.handleBeforeRender = this.releaseScrollLock.bind(this)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
    document.addEventListener("turbo:before-render", this.handleBeforeRender)

    this.reset()
    this.dismissWhenReady()

    sessionStorage.setItem("landing_loader_shown", "true")
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
    
    // Delay releasing the lock until the fade is partially complete
    // This also keeps the chat widget hidden until the brand intro is finished
    setTimeout(() => {
      this.releaseScrollLock()
    }, 500)
  }

  reset() {
    if (!this.hasOverlayTarget) return

    this.clearTimers()
    this.overlayTarget.classList.remove("is-hidden")
    document.documentElement.classList.add("landing-loader-active")
  }

  prepareForCache() {
    if (!this.hasOverlayTarget) return

    this.clearTimers()
    this.overlayTarget.classList.remove("is-hidden")
    this.releaseScrollLock()
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
