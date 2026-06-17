import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  format() {
    const original = this.element.value
    const formatted = original
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "")

    if (original !== formatted) {
      this.element.value = formatted
    }
  }
}
