import { Controller } from "@hotwired/stimulus"

// Shows either the text editor or the PDF upload, never both.
//
// The source is picked with a PanelsUI select menu, whose value lives on the
// native select it wraps. The change event bubbles, so this controller reads
// the value off the event rather than holding a target on the control.
export default class extends Controller {
  static targets = ["textContent", "pdfUpload"]
  static values = { sourceType: { type: String, default: "text" } }

  sourceTypeValueChanged() {
    const pdf = this.sourceTypeValue === "pdf"

    this.textContentTarget.classList.toggle("hidden", pdf)
    this.pdfUploadTarget.classList.toggle("hidden", !pdf)
  }

  sourceTypeChanged(event) {
    this.sourceTypeValue = event.target.value
  }
}
