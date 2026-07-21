import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "row", "total", "continueButton"]
  static values = { currency: String }

  connect() {
    this.recalculate()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.rowTargets.forEach((checkbox) => { checkbox.checked = checked })
    this.recalculate()
  }

  recalculate() {
    const total = this.rowTargets.reduce((sum, checkbox) => {
      return checkbox.checked ? sum + this.number(checkbox.dataset.amount) : sum
    }, 0)

    if (this.hasTotalTarget) {
      this.totalTarget.textContent = `${this.currencyValue} ${total.toFixed(2)}`
    }

    if (this.hasContinueButtonTarget) {
      this.continueButtonTarget.disabled = total <= 0
    }

    this.syncSelectAllState()
  }

  syncSelectAllState() {
    if (!this.hasSelectAllTarget) return

    const allChecked = this.rowTargets.length > 0 && this.rowTargets.every((checkbox) => checkbox.checked)
    this.selectAllTarget.checked = allChecked
  }

  number(value) {
    const parsed = Number.parseFloat(value)
    return Number.isFinite(parsed) ? parsed : 0
  }
}
