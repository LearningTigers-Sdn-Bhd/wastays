import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["reviewSection", "chargeChoice", "customFields", "amountInput", "displayAmount"]
  static values = {
    baseAmount: Number,
    currency: { type: String, default: "MYR" },
    bookingId: String
  }

  connect() {
    this.updateUI()
  }

  updateUI() {
    const choice = this.chargeChoiceTargets.find(r => r.checked).value

    if (choice === "true") {
      this.customFieldsTarget.classList.remove("hidden")
      this.updateCalculation()
    } else {
      this.customFieldsTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      this.notifySettlement(0)
    }
  }

  updateCalculation() {
    const type = this.element.querySelector(`[name="early_departures[${this.bookingIdValue}][type]"]`)?.value || "amount"
    const value = parseFloat(this.element.querySelector(`[name="early_departures[${this.bookingIdValue}][value]"]`)?.value) || 0
    let finalAmount = 0

    if (type === "percentage") {
      finalAmount = this.baseAmountValue * (value / 100)
    } else {
      finalAmount = value
    }

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    this.notifySettlement(finalAmount)
  }

  notifySettlement(amount) {
    this.element.dispatchEvent(new CustomEvent("checkout-settlement:charge-changed", {
      bubbles: true,
      detail: { amount, bookingId: this.bookingIdValue }
    }))
  }
}
