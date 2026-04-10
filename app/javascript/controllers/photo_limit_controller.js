import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "warning", "counter"]
  static values = {
    existingCount: Number,
    maxCount: { type: Number, default: 20 },
  }

  connect() {
    this.update()
  }

  update() {
    const selectedCount = this.hasInputTarget ? this.inputTarget.files.length : 0
    const totalCount = this.existingCountValue + selectedCount

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${totalCount}/${this.maxCountValue} photos`
    }

    if (this.hasWarningTarget) this.warningTarget.classList.add("hidden")
  }
}
