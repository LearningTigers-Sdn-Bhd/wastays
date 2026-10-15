import { Controller } from "@hotwired/stimulus"

// Posts to a "test this integration" endpoint and reports the reply in place.
//
// It sends the form with the request, so an admin can try settings before
// saving them. The controller is mounted on the <form>, so this.element is it.
export default class extends Controller {
  static targets = ["button", "status"]
  static values = { url: String, testingLabel: { type: String, default: "Testing..." } }

  async run() {
    const button = this.buttonTarget
    const originalLabel = button.innerHTML

    button.disabled = true
    button.textContent = this.testingLabelValue
    this.report("Testing these settings...", "text-muted-foreground")

    // The form saves with PATCH, so it carries a _method field. Rack rewrites
    // the verb from it, which would turn this POST into a PATCH and miss the
    // route. The test endpoint is POST only, so the field goes.
    const body = new URLSearchParams(new FormData(this.element))
    body.delete("_method")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content ?? "",
          Accept: "application/json"
        },
        body
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
