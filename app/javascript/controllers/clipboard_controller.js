import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { text: String }

  async copy(event) {
    try {
      await navigator.clipboard.writeText(event.currentTarget.dataset.clipboardTextValue || this.textValue)
      this.statusTarget.textContent = "Copied to clipboard."
    } catch (_) {
      this.statusTarget.textContent = "Copy failed. Select and copy the value manually."
    }
  }
}
