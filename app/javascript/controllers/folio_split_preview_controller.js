import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["amount", "percent", "summary"]
  static values = { total: Number, currency: String }

  connect() { this.update() }

  update() {
    const amount = this.amountTarget.value
    const percent = this.percentTarget.value
    if (amount && percent) {
      this.summaryTarget.textContent = "Enter an amount or a percentage, not both."
      return
    }
    const target = Math.round((percent ? this.totalValue * Number(percent) / 100 : Number(amount)) * 100) / 100
    if (!(target > 0 && target < this.totalValue)) {
      this.summaryTarget.textContent = "Enter a partial amount. To move the full amount, use Move."
      return
    }
    this.summaryTarget.textContent = `Destination: ${this.currencyValue} ${target.toFixed(2)} · Source remainder: ${this.currencyValue} ${(this.totalValue - target).toFixed(2)}. Attached taxes split proportionally.`
  }
}
