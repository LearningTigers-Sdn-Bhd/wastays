import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.timer = null
    this.historyTimer = null
    this.submitting = false
    this.pendingSignature = null
    this.onPopState = this.restoreForLocation.bind(this)
    this.onTurboRender = this.restoreForLocation.bind(this)
    window.addEventListener("popstate", this.onPopState)
    document.addEventListener("turbo:render", this.onTurboRender)
    document.addEventListener("turbo:load", this.onTurboRender)
  }

  disconnect() {
    window.removeEventListener("popstate", this.onPopState)
    document.removeEventListener("turbo:render", this.onTurboRender)
    document.removeEventListener("turbo:load", this.onTurboRender)
    this.cancelPending()
    if (this.historyTimer !== null) window.clearTimeout(this.historyTimer)
    this.submitting = false
    this.pendingSignature = null
  }

  submit() {
    this.cancelPending()
    this.timer = window.setTimeout(() => this.submitNow(), 50)
  }

  submitNow() {
    this.timer = null
    const signature = new URLSearchParams(new FormData(this.element)).toString()
    if (this.submitting && signature === this.pendingSignature) return

    this.pendingSignature = signature
    this.element.requestSubmit()
  }

  start() {
    this.submitting = true
  }

  finish() {
    this.submitting = false
  }

  restoreForLocation() {
    if (this.historyTimer !== null) window.clearTimeout(this.historyTimer)
    this.historyTimer = window.setTimeout(() => {
      this.historyTimer = null
      if (this.matchesLocation()) return

      const frame = this.element.closest("turbo-frame")
      if (!frame) return

      frame.addEventListener("turbo:frame-load", () => frame.removeAttribute("src"), { once: true })
      frame.setAttribute("src", window.location.href)
    }, 0)
  }

  matchesLocation() {
    const location = new URL(window.location.href)
    const form = new URLSearchParams(new FormData(this.element))
    const keys = [
      "view", "start_date", "date", "days", "room_type_id",
      "rate_plan_id", "occupancy", "physical_status", "room_state", "group_by", "room_group_id"
    ]

    return keys.every((key) => (location.searchParams.get(key) || "") === (form.get(key) || ""))
  }

  cancelPending() {
    if (this.timer === null) return

    window.clearTimeout(this.timer)
    this.timer = null
  }
}
