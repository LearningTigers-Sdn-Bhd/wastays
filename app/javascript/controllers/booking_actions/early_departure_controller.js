import { Controller } from "@hotwired/stimulus"

// Early-departure charge calculator for the checkout Sheet (booking-actions
// namespace, isolated from the legacy implementation). Computes the penalty and
// announces it — including the folio it routes to — so the settlement controller
// can fold it into that folio's amount.
//
// The amount written here is a display/settlement preview only: the server
// recomputes it in CheckoutsController#calculated_early_departure_charge, and on
// the "follow policy" path it comes from the hotel's policy, not from this form.
export default class extends Controller {
  static targets = ["chargeFields", "customFields", "policyFields", "amountInput", "displayAmount"]
  static values = {
    baseAmount: Number,
    policyAmount: Number,
    currency: { type: String, default: "MYR" },
    bookingId: String,
    targetFolioId: String,
    eventPrefix: { type: String, default: "booking-actions--checkout-settlement" }
  }

  connect() {
    this.updateUI()
  }

  get applyCharge() {
    return this.fieldValue("apply_charge", { checked: true }) === "true"
  }

  get chargeSource() {
    if (!this.hasPolicyFieldsTarget) return "custom"

    return this.fieldValue("charge_source", { checked: true }) || "policy"
  }

  fieldValue(name, { checked = false } = {}) {
    const selector = `[name="early_departures[${this.bookingIdValue}][${name}]"]${checked ? ":checked" : ""}`
    return this.element.querySelector(selector)?.value
  }

  updateUI() {
    if (!this.applyCharge) {
      this.chargeFieldsTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      this.notifySettlement(0, { applyCharge: false, type: "amount", value: 0 })
      return
    }

    this.chargeFieldsTarget.classList.remove("hidden")

    if (this.chargeSource === "policy") {
      this.policyFieldsTarget.classList.remove("hidden")
      this.customFieldsTarget.classList.add("hidden")
      this.amountInputTarget.value = this.policyAmountValue.toFixed(2)
      this.notifySettlement(this.policyAmountValue, { applyCharge: true, type: "policy", value: this.policyAmountValue })
      return
    }

    if (this.hasPolicyFieldsTarget) this.policyFieldsTarget.classList.add("hidden")
    this.customFieldsTarget.classList.remove("hidden")
    this.updateCalculation()
  }

  updateCalculation() {
    if (!this.applyCharge || this.chargeSource === "policy") return

    const type = this.fieldValue("type") || "amount"
    const value = parseFloat(this.fieldValue("value")) || 0
    const finalAmount = type === "percentage" ? this.baseAmountValue * (value / 100) : value

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    this.notifySettlement(finalAmount, { applyCharge: true, type, value })
  }

  notifySettlement(amount, details) {
    this.element.dispatchEvent(new CustomEvent(`${this.eventPrefixValue}:charge-changed`, {
      bubbles: true,
      detail: { amount, bookingId: this.bookingIdValue, targetFolioId: this.targetFolioIdValue, ...details }
    }))
  }
}
