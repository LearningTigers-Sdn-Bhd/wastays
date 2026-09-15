import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["workingDate", "systemDate"]
  static values = {
    url: String,
    interval: { type: Number, default: 60000 }
  }

  connect() {
    this.visibilityChanged = this.visibilityChanged.bind(this)
    document.addEventListener("visibilitychange", this.visibilityChanged)

    if (document.visibilityState === "visible") {
      this.refresh()
      this.startTimer()
    }
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibilityChanged)
    this.stopTimer()
    this.abortRequest()
  }

  visibilityChanged() {
    if (document.visibilityState === "hidden") {
      this.stopTimer()
      this.abortRequest()
      return
    }

    this.refresh()
    this.startTimer()
  }

  startTimer() {
    this.stopTimer()
    this.timer = window.setInterval(() => this.refresh(), this.intervalValue)
  }

  stopTimer() {
    if (this.timer) window.clearInterval(this.timer)
    this.timer = null
  }

  abortRequest() {
    this.request?.abort()
    this.request = null
  }

  async refresh() {
    if (!this.hasUrlValue || this.request || document.visibilityState === "hidden") return

    const request = new AbortController()
    this.request = request

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: request.signal
      })
      if (!response.ok) return

      const dates = await response.json()
      this.updateTargets(this.workingDateTargets, dates.working_date)
      this.updateTargets(this.systemDateTargets, dates.system_date)
    } catch {
      // Keep the last server-rendered values and try again at the next refresh.
    } finally {
      if (this.request === request) this.request = null
    }
  }

  updateTargets(targets, date) {
    if (!date || typeof date.label !== "string") return

    targets.forEach((target) => {
      target.textContent = date.label
      if (date.value) target.setAttribute("datetime", date.value)
      else target.removeAttribute("datetime")
    })
  }
}
