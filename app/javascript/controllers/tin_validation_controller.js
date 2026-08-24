import { Controller } from "@hotwired/stimulus"

// Checks a tax number against LHDN as soon as the desk has both it and an
// identity to match it to. Advisory: it never blocks the form, because LHDN
// being slow must not stop a check-in.
export default class extends Controller {
  static targets = ["tin", "idValue", "documentType", "feedback"]
  static values = { url: String }

  // For a manually-triggered "Test connection" button rather than a field
  // blur: the tin/idValue here are fixed hidden values that never change
  // between clicks, so the de-dupe guard in check() (which exists to avoid
  // re-checking a field the guest hasn't finished editing) would otherwise
  // silently no-op every click after the first.
  forceCheck() {
    this.lastChecked = null
    this.check()
  }

  check() {
    const tin = this.hasTinTarget ? this.tinTarget.value.trim() : ""
    const idValue = this.hasIdValueTarget ? this.idValueTarget.value.trim() : ""

    // Nothing useful to ask yet.
    if (!tin || !idValue) {
      this.render(null, "")
      return
    }

    if (tin === this.lastChecked) return
    this.lastChecked = tin

    this.render("checking", "Checking with LHDN…")

    const body = new FormData()
    body.append("tin", tin)
    body.append("id_value", idValue)
    if (this.hasDocumentTypeTarget) body.append("document_type", this.documentTypeTarget.value)

    fetch(this.urlValue, {
      method: "POST",
      body,
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
        Accept: "application/json"
      }
    })
      .then((response) => (response.ok ? response.json() : Promise.reject(response)))
      .then((data) => this.render(data.status, data.message))
      .catch(() => this.render(null, ""))
  }

  render(status, message) {
    if (!this.hasFeedbackTarget) return

    this.feedbackTarget.textContent = message || ""
    this.feedbackTarget.hidden = !message
    this.feedbackTarget.className = [
      "mt-1 text-xs",
      status === "valid" ? "text-foreground" : "",
      status === "invalid" ? "text-destructive" : "",
      status === "unknown" || status === "checking" ? "text-muted-foreground" : ""
    ].filter(Boolean).join(" ")
  }
}
