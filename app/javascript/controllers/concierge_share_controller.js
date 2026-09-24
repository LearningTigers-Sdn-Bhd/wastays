import { Controller } from "@hotwired/stimulus"

// The native share sheet where it exists (every mobile browser this page is
// actually opened in); otherwise the link goes to the clipboard and the
// button says so for a moment, since there is nowhere else on this layout
// to put that confirmation -- the concierge layout carries no toast viewport.
export default class extends Controller {
  static values = { title: String, url: String }
  static targets = ["label"]

  async share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: this.titleValue, url: this.urlValue })
      } catch (error) {
        // AbortError when the guest dismisses the native sheet -- not a failure.
      }
      return
    }

    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.flash("Copied!")
    } catch (error) {
      this.flash("Copy failed")
    }
  }

  flash(message) {
    if (this.flashTimer) window.clearTimeout(this.flashTimer)

    const original = this.originalLabel ?? this.labelTarget.textContent
    this.originalLabel = original
    this.labelTarget.textContent = message

    this.flashTimer = window.setTimeout(() => {
      this.labelTarget.textContent = original
      this.flashTimer = null
    }, 1500)
  }
}
