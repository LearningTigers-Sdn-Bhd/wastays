import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["appliesTo", "targetField", "targetInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    const showTargetField = this.appliesToTarget.value !== ""

    this.targetFieldTarget.classList.toggle("hidden", !showTargetField)
    this.targetInputTarget.disabled = !showTargetField

    if (!showTargetField) {
      this.targetInputTarget.value = ""
    }
  }
}
