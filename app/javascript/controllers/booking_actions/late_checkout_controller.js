import { Controller } from "@hotwired/stimulus"

// Late-checkout charge calculator for the booking-action Sheet. Pure UI: shows
// or hides the charge/checkout sections based on approve/reject, and computes
// the amount (standard rate, or rate + fixed/percentage adjustment) into the
// hidden amount field. Copied into the booking-actions namespace so the Sheet
// flow does not depend on the legacy late-checkout implementation.
export default class extends Controller {
  static targets = ["chargeSection", "checkoutSection", "customSection", "toggleRadio", "typeRadio", "customType", "customValue", "displayAmount", "amountInput"]
  static values = {
    baseAmount: Number,
    currency: { type: String, default: "MYR" }
  }

  connect() {
    this.updateUI()
  }

  updateUI() {
    const chargeToggle = this.toggleRadioTargets.find((radio) => radio.checked).value

    if (chargeToggle === "none") {
      this.chargeSectionTarget.classList.add("hidden")
      this.checkoutSectionTarget.classList.add("hidden")
      this.customSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      return
    }

    this.chargeSectionTarget.classList.remove("hidden")
    this.checkoutSectionTarget.classList.remove("hidden")
    const selectedType = this.typeRadioTargets.find((radio) => radio.checked).value

    if (selectedType === "custom") {
      this.customSectionTarget.classList.remove("hidden")
      this.updateCalculation()
    } else {
      this.customSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = this.baseAmountValue.toFixed(2)
    }
  }

  updateCalculation() {
    const chargeToggle = this.toggleRadioTargets.find((radio) => radio.checked).value
    if (chargeToggle === "none") return

    const selectedType = this.typeRadioTargets.find((radio) => radio.checked).value
    const type = this.customTypeTarget.value
    const value = parseFloat(this.customValueTarget.value) || 0
    let finalAmount = this.baseAmountValue

    if (selectedType === "custom") {
      const adjustment = type === "percentage" ? this.baseAmountValue * (value / 100) : value
      finalAmount += adjustment
    }

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
