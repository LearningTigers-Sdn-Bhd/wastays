import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "amountInput",
    "submitButton",
    "outstandingAmount",
    "totalChargesAmount",
    "actionSelect",
    "detailRow",
    "paymentFields",
    "reasonFields",
    "directBillFields"
  ]
  static values = {
    currency: { type: String, default: "MYR" },
    requiredAmount: Number,
    totalCharges: Number
  }

  connect() {
    this.currentRequiredAmount = this.roundMoney(this.requiredAmountValue)
    this.currentEarlyDepartureCharge = 0
    this.updateSettlementDetails()
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
    if (!this.hasSubmitButtonTarget) {
      return
    }

    let valid = true
    if (this.hasAmountInputTarget && this.currentRequiredAmount > 0) {
      const amount = this.roundMoney(Number.parseFloat(this.amountInputTarget.value || "0"))
      valid = amount === this.currentRequiredAmount
    }

    this.submitButtonTarget.disabled = !valid
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !valid)
    this.submitButtonTarget.classList.toggle("opacity-50", !valid)
    this.submitButtonTarget.classList.toggle("hover:bg-slate-700", valid)
  }

  updateSummary() {
    if (this.hasOutstandingAmountTarget) {
      this.outstandingAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(this.currentRequiredAmount)}`
    }

    if (this.hasTotalChargesAmountTarget) {
      this.totalChargesAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(this.totalChargesValue + this.currentEarlyDepartureCharge)}`
    }
  }

  updateSettlementDetails() {
    this.detailRowTargets.forEach((row) => {
      const folioId = row.dataset.folioId
      const action = this.selectedActionFor(folioId)
      const visible = ["pay_now", "direct_bill", "keep_open", "manager_review", "write_off_approval"].includes(action)

      row.classList.toggle("hidden", !visible)
      this.toggleFields(row, "paymentFields", action === "pay_now")
      this.toggleFields(row, "reasonFields", ["keep_open", "manager_review", "write_off_approval"].includes(action))
      this.toggleFields(row, "directBillFields", action === "direct_bill")
    })
  }

  selectedActionFor(folioId) {
    const select = this.actionSelectTargets.find((target) => target.dataset.folioId === folioId)
    return select ? select.value : ""
  }

  toggleFields(row, targetName, enabled) {
    row.querySelectorAll(`[data-checkout-settlement-target='${targetName}']`).forEach((container) => {
      container.classList.toggle("hidden", !enabled)
      container.querySelectorAll("input, select, textarea").forEach((input) => {
        if (input.dataset.requiredForAction === "true") {
          input.required = enabled
        }
      })
    })
  }

  formatMoney(value) {
    return this.roundMoney(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }

  roundMoney(value) {
    return Math.round((Number.isFinite(value) ? value : 0) * 100) / 100
  }
}
