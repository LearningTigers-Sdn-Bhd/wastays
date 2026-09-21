import { Controller } from "@hotwired/stimulus"

// Posts to a "test this integration" endpoint and reports the reply in place.
//
// The endpoint reads the SAVED settings, not what is currently typed in the
// form, so the status line says so while the request is in flight.
export default class extends Controller {
  static targets = ["button", "status"]
  static values = { url: String, testingLabel: { type: String, default: "Testing..." } }

  async run() {
    const button = this.buttonTarget
    const originalLabel = button.innerHTML

    button.disabled = true
    button.textContent = this.testingLabelValue
    this.report("Testing the saved settings...", "text-muted-foreground")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content ?? "",
          "Content-Type": "application/json",
          Accept: "application/json"
        }
      })

      const data = await response.json()
      this.report(data.message, data.success ? "text-success" : "text-destructive")
    } catch {
      this.report("Could not reach the server.", "text-destructive")
    } finally {
      button.disabled = false
      button.innerHTML = originalLabel
    }
  }

  // The message itself carries the outcome. Colour only reinforces it, so a
  // reader who cannot see the colour loses nothing.
  report(message, toneClass) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("text-muted-foreground", "text-success", "text-destructive")
    this.statusTarget.classList.add(toneClass)
  }
}
