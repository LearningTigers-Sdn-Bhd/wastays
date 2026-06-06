import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sourceType", "textContent", "pdfUpload"]

  toggleSourceType() {
    const value = this.sourceTypeTarget.value

    if (value === "pdf") {
      this.textContentTarget.classList.add("hidden")
      this.pdfUploadTarget.classList.remove("hidden")
    } else {
      this.textContentTarget.classList.remove("hidden")
      this.pdfUploadTarget.classList.add("hidden")
    }
  }
}
