import { Controller } from "@hotwired/stimulus"

// Blacklisting needs a reason, so it needs a form rather than a text-only
// confirm. One dialog serves the whole directory: the row that opens it hands
// over the form action and the guest name, so a page of 25 guests still ships
// one dialog instead of 25.
export default class extends Controller {
  static targets = ["form", "name"]

  open({ params }) {
    if (this.hasFormTarget && params.url) {
      this.formTarget.action = params.url
      this.formTarget.reset()
    }

    if (this.hasNameTarget && params.name) {
      this.nameTarget.textContent = params.name
    }
  }
}
