import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["switch", "reasonWrapper", "reasonInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    const showReason = this.switchTarget.checked && this.switchTarget.dataset.alreadyPrimary !== "true"
    this.reasonWrapperTarget.classList.toggle("hidden", !showReason)
    this.reasonInputTarget.required = showReason
    if (!showReason) this.reasonInputTarget.value = ""
  }
}
