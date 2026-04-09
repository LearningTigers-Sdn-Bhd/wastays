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
    const remainingCount = Math.max(this.maxCountValue - this.existingCountValue, 0)

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${totalCount}/${this.maxCountValue} photos`
    }

    if (!this.hasWarningTarget) return

    if (totalCount > this.maxCountValue) {
      this.warningTarget.textContent = `Only ${this.maxCountValue} photos can be uploaded per hotel. You already have ${this.existingCountValue} photo${this.existingCountValue === 1 ? "" : "s"} uploaded, so please select ${remainingCount} or fewer additional photo${remainingCount === 1 ? "" : "s"}.`
      this.warningTarget.classList.remove("hidden")
    } else {
      this.warningTarget.classList.add("hidden")
    }
  }
}
