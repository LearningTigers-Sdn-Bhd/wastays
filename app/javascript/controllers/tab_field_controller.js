import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = {
    value: String
  }

  update(event) {
    event.preventDefault()
    
    const value = event.currentTarget.dataset.tabValue || this.valueValue
    this.inputTarget.value = value
    
    // Submit the form if it belongs to one
    const form = this.inputTarget.form
    if (form) {
      if (typeof form.requestSubmit === "function") {
        form.requestSubmit()
      } else {
        form.submit()
      }
    }
  }
}
