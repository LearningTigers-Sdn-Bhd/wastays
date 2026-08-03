import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { statusUrl: String }

  connect() {
    if (!this.hasStatusUrlValue) return

    this.poll = this.poll.bind(this)
    this.visibilityChanged = this.visibilityChanged.bind(this)
    document.addEventListener("visibilitychange", this.visibilityChanged)
    this.timer = window.setInterval(this.poll, 2000)
    this.poll()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibilityChanged)
    if (this.timer) window.clearInterval(this.timer)
  }

  async poll() {
    if (this.polling || document.visibilityState === "hidden") return
    this.polling = true
    try {
      const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Night audit status could not be checked")
      const result = await response.json()

      if (result.state === "completed") return this.complete(result.refresh_url)
      if (["blocked", "failed"].includes(result.state)) return this.refreshSheet(result.sheet_url)
    } catch (error) {
      this.showPollingError(error.message)
    } finally {
      this.polling = false
    }
  }

  visibilityChanged() {
    if (document.visibilityState === "visible") this.poll()
  }

  complete(url) {
    if (this.timer) window.clearInterval(this.timer)
    const frame = this.element.closest("turbo-frame")
    const stream = document.createElement("turbo-stream")
    stream.setAttribute("action", "complete_sheet")
    stream.setAttribute("target", frame?.id || "booking_action_sheet")
    stream.setAttribute("url", url)
    Turbo.renderStreamMessage(stream.outerHTML)
  }

  refreshSheet(url) {
    if (this.timer) window.clearInterval(this.timer)
    const frame = this.element.closest("turbo-frame")
    if (!frame) return window.location.assign(url)
    frame.src = url
    frame.reload()
  }

  showPollingError(message) {
    if (this.errorShown) return
    this.errorShown = true
    window.toast?.("Night audit status unavailable", { type: "error", description: message })
  }
}
