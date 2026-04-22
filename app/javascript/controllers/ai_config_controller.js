import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["geminiField", "openaiField", "providerSelect"]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    const provider = this.providerSelectTarget.value
    
    if (provider === "openai") {
      this.geminiFieldTarget.classList.add("hidden")
      this.openaiFieldTarget.classList.remove("hidden")
    } else {
      this.geminiFieldTarget.classList.remove("hidden")
      this.openaiFieldTarget.classList.add("hidden")
    }
  }
}
