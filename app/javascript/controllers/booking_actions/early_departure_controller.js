import { Controller } from "@hotwired/stimulus"

// Early-departure charge calculator for the checkout Sheet (booking-actions
// namespace, isolated from the legacy implementation). Computes the manual
// early-departure penalty and announces it — including the folio it routes to —
// so the settlement controller can fold it into that folio's amount.
export default class extends Controller {
  static targets = ["customFields", "amountInput", "displayAmount"]
  static values = {
    baseAmount: Number,
    currency: { type: String, default: "MYR" },
    bookingId: String,
    targetFolioId: String,
    eventPrefix: { type: String, default: "booking-actions--checkout-settlement" }
  }

  connect() {
    this.updateUI()
  }

  updateUI() {
    const choice = this.element.querySelector(`[name="early_departures[${this.bookingIdValue}][apply_charge]"]:checked`)?.value || "false"

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
    const finalAmount = type === "percentage" ? this.baseAmountValue * (value / 100) : value

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    this.notifySettlement(finalAmount)
  }

  notifySettlement(amount) {
    this.element.dispatchEvent(new CustomEvent(`${this.eventPrefixValue}:charge-changed`, {
      bubbles: true,
      detail: { amount, bookingId: this.bookingIdValue, targetFolioId: this.targetFolioIdValue }
    }))
  }
}
