import { Controller } from "@hotwired/stimulus"

// A description clamped to a few lines on a phone, with a button to reveal
// the rest. Nothing server-rendered changes -- both states are the same
// paragraph, only the clamp class toggles.
export default class extends Controller {
  static targets = ["text", "button"]

  connect() {
    this.expanded = false

    // scrollHeight only exceeds clientHeight when the clamp is actually
    // cutting something off -- no button when the text already fits, so
    // there is never a "Read more" with nothing more behind it.
    if (this.textTarget.scrollHeight <= this.textTarget.clientHeight + 1) {
      this.buttonTarget.hidden = true
    }
  }

  toggle() {
    this.expanded = !this.expanded
    this.textTarget.classList.toggle("line-clamp-4", !this.expanded)
    this.buttonTarget.textContent = this.expanded ? "Read less" : "Read more"
  }
}
