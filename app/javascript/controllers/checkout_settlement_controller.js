import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["amountInput", "submitButton", "outstandingAmount", "totalChargesAmount"]
  static values = {
    currency: { type: String, default: "MYR" },
    requiredAmount: Number,
    totalCharges: Number
  }

  connect() {
    this.currentRequiredAmount = this.roundMoney(this.requiredAmountValue)
    this.currentEarlyDepartureCharge = 0
    this.validate()
  }

  updateEarlyDepartureCharge(event) {
    const previousRequiredAmount = this.currentRequiredAmount
    const amount = this.roundMoney(Number.parseFloat(event.detail?.amount || "0"))
    this.currentEarlyDepartureCharge = amount
    this.currentRequiredAmount = this.roundMoney(this.requiredAmountValue + this.currentEarlyDepartureCharge)

    if (this.hasAmountInputTarget) {
      this.amountInputTarget.max = this.currentRequiredAmount.toFixed(2)

      if (this.roundMoney(Number.parseFloat(this.amountInputTarget.value || "0")) === previousRequiredAmount) {
        this.amountInputTarget.value = this.currentRequiredAmount.toFixed(2)
      }
    }

    this.updateSummary()
    this.validate()
  }

  validate() {
    if (!this.hasAmountInputTarget || !this.hasSubmitButtonTarget || this.currentRequiredAmount <= 0) {
      return
    }

    const amount = this.roundMoney(Number.parseFloat(this.amountInputTarget.value || "0"))
    const valid = amount === this.currentRequiredAmount

    this.submitButtonTarget.disabled = !valid
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !valid)
    this.submitButtonTarget.classList.toggle("opacity-50", !valid)
    this.submitButtonTarget.classList.toggle("hover:bg-slate-700", valid)
  }

  updateSummary() {
    if (this.hasOutstandingAmountTarget) {
      this.outstandingAmountTarget.textContent = this.formatMoney(this.currentRequiredAmount)
    }

    if (this.hasTotalChargesAmountTarget) {
      this.totalChargesAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(this.totalChargesValue + this.currentEarlyDepartureCharge)}`
    }
  }

  formatMoney(value) {
    return this.roundMoney(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }

  roundMoney(value) {
    return Math.round((Number.isFinite(value) ? value : 0) * 100) / 100
  }
}
