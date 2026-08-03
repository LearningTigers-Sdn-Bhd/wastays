import { Controller } from "@hotwired/stimulus"

// Late-checkout charge calculator for the booking-action Sheet. Pure UI: shows
// or hides the charge/checkout sections based on the resolution, and computes
// the amount (standard rate, or rate + fixed/percentage adjustment) into the
// hidden amount field. The choice controls are PanelsUI primitives (RadioGroup,
// SelectMenu) that own their own markup, so we read them by field name rather
// than by per-control Stimulus targets.
export default class extends Controller {
  static targets = ["chargeSection", "checkoutSection", "standardSection", "customSection", "displayAmount", "amountInput", "submitButton"]
  static values = {
    baseAmount: Number,
    currency: { type: String, default: "MYR" }
  }

  connect() {
    this.updateUI()
  }

  get resolution() {
    const checked = this.element.querySelector('input[name="resolution"]:checked')
    return checked ? checked.value : "charge"
  }

  get calculationType() {
    const checked = this.element.querySelector('input[name="charge_calculation"]:checked')
    return checked ? checked.value : "standard"
  }

  get customType() {
    const control = this.element.querySelector('[name="custom_type"]')
    return control ? control.value : "amount"
  }

  get customValue() {
    const control = this.element.querySelector('[name="custom_value"]')
    return control ? parseFloat(control.value) || 0 : 0
  }

  updateUI() {
    if (this.resolution === "reject") {
      this.submitButtonTarget.textContent = "Reject late checkout"
      this.submitButtonTarget.dataset.turboSubmitsWith = "Rejecting…"
      this.chargeSectionTarget.classList.add("hidden")
      this.checkoutSectionTarget.classList.add("hidden")
      this.customSectionTarget.classList.add("hidden")
      this.standardSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      return
    }

    this.checkoutSectionTarget.classList.remove("hidden")

    if (this.resolution === "waive") {
      this.submitButtonTarget.textContent = "Approve without charge"
      this.submitButtonTarget.dataset.turboSubmitsWith = "Approving…"
      this.chargeSectionTarget.classList.add("hidden")
      this.customSectionTarget.classList.add("hidden")
      this.standardSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      return
    }

    this.submitButtonTarget.textContent = "Approve and apply charges"
    this.submitButtonTarget.dataset.turboSubmitsWith = "Approving…"
    this.chargeSectionTarget.classList.remove("hidden")

    if (this.calculationType === "custom") {
      this.customSectionTarget.classList.remove("hidden")
      this.standardSectionTarget.classList.add("hidden")
      this.updateCalculation()
    } else {
      this.customSectionTarget.classList.add("hidden")
      this.standardSectionTarget.classList.remove("hidden")
      this.amountInputTarget.value = this.baseAmountValue.toFixed(2)
    }
  }

  updateCalculation() {
    if (this.resolution !== "charge") return

    let finalAmount = this.baseAmountValue

    if (this.calculationType === "custom") {
      const adjustment = this.customType === "percentage" ? this.baseAmountValue * (this.customValue / 100) : this.customValue
      finalAmount += adjustment
    }

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
