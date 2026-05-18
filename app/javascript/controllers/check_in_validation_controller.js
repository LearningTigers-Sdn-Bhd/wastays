import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "reason", "submitButton"]

  connect() {
    this.validate()
  }

  validate() {
    if (this.hasCheckboxTarget && this.hasReasonTarget) {
      if (this.checkboxTarget.checked) {
        this.reasonTarget.required = true
        this.reasonTarget.parentElement.classList.remove("opacity-50")
      } else {
        this.reasonTarget.required = false
        this.reasonTarget.parentElement.classList.add("opacity-50")
        this.reasonTarget.classList.remove("border-red-500", "ring-1", "ring-red-500")
      }
    }
  }

  clearError() {
    this.reasonTarget.classList.remove("border-red-500", "ring-1", "ring-red-500")
  }

  handleSubmit(event) {
    if (this.hasCheckboxTarget && this.checkboxTarget.checked && !this.reasonTarget.value.trim()) {
      event.preventDefault()
      this.reasonTarget.classList.add("border-red-500", "ring-1", "ring-red-500")
      this.reasonTarget.focus()
    }
  }
}
