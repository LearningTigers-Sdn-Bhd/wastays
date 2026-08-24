import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dialog",
    "review",
    "progress",
    "ready",
    "failed",
    "message",
    "progressLabel",
    "progressMeta",
    "progressHint",
    "downloadLink",
    "submitButton"
  ]

  static values = {
    requestUrl: String,
    statusUrl: String
  }

  connect() {
    this.pollTimer = null
    this.progressStartedAt = null
  }

  disconnect() {
    this.stopPolling()
  }

  open(event) {
    event.preventDefault()
    this.progressStartedAt = null
    this.disableSubmit(false)
    this.showState("review")
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.stopPolling()
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  async submit(event) {
    event.preventDefault()
    this.disableSubmit(true)
    this.progressStartedAt = Date.now()
    this.showProgress({
      title: "Submitting your request",
      message: "We are sending your request to LHDN now.",
      meta: "This usually updates automatically within a short while.",
      hint: "You can keep this window open while we check for the final document."
    })

    try {
      const response = await fetch(this.requestUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        credentials: "same-origin"
      })

      const data = await response.json()
      this.showProgress({
        title: "Preparing your e-invoice",
        message: data.message || "We are preparing your e-invoice now.",
        meta: this.progressMetaText(),
        hint: "We will keep checking automatically and show the document here once it is ready."
      })
      this.startPolling()
    } catch (_error) {
      this.showState("failed", "We could not start your e-invoice request. Please try again.")
      this.disableSubmit(false)
    }
  }

  startPolling() {
    this.stopPolling()
    this.poll()
    this.pollTimer = setInterval(() => this.poll(), 3000)
  }

  stopPolling() {
    if (this.pollTimer) clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async poll() {
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()

      if (data.status === "ready") {
        this.stopPolling()
        this.downloadLinkTarget.href = data.download_url
        this.showState("ready", data.message || "Your e-invoice is ready.")
        return
      }

      if (data.status === "failed") {
        this.stopPolling()
        this.showState("failed", data.message || "We could not generate the e-invoice yet.")
        return
      }

      this.showProgress({
        title: "Preparing your e-invoice",
        message: data.message || "We are preparing your e-invoice now.",
        meta: this.progressMetaText(),
        hint: "No manual refresh needed. We are checking LHDN every few seconds for you."
      })
    } catch (_error) {
      this.showProgress({
        title: "Still checking LHDN",
        message: "Still working on your e-invoice. We will keep checking for you.",
        meta: this.progressMetaText(),
        hint: "If you close this window, you can return to the booking page and check again later."
      })
    }
  }

  showState(state, message = null) {
    this.reviewTarget.classList.toggle("hidden", state !== "review")
    this.progressTarget.classList.toggle("hidden", state !== "progress")
    this.readyTarget.classList.toggle("hidden", state !== "ready")
    this.failedTarget.classList.toggle("hidden", state !== "failed")

    if (message && this.hasMessageTarget) {
      this.messageTargets.forEach((target) => {
        target.textContent = message
      })
    }
  }

  showProgress({ title, message, meta, hint }) {
    this.showState("progress", message)
    if (this.hasProgressLabelTarget) this.progressLabelTarget.textContent = title
    if (this.hasProgressMetaTarget) this.progressMetaTarget.textContent = meta
    if (this.hasProgressHintTarget) this.progressHintTarget.textContent = hint
  }

  disableSubmit(disabled) {
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = disabled
  }

  progressMetaText() {
    const elapsedSeconds = this.progressStartedAt ? Math.max(0, Math.floor((Date.now() - this.progressStartedAt) / 1000)) : 0
    if (elapsedSeconds < 5) return "Checking with LHDN now."
    if (elapsedSeconds < 60) return `Auto-checking every few seconds. Waiting about ${elapsedSeconds}s so far.`
    const minutes = Math.floor(elapsedSeconds / 60)
    const seconds = elapsedSeconds % 60
    return `Auto-checking every few seconds. Waiting ${minutes}m ${seconds}s so far.`
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
