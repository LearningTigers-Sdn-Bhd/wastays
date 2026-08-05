import { Controller } from "@hotwired/stimulus"

// Late-checkout charge calculator for the booking-action Sheet. Pure UI: shows
// or hides the charge/checkout sections based on the resolution, and computes
// the custom amount (rate + fixed/percentage adjustment) into the hidden amount
// field. On the "follow policy" path the hidden amount is not authoritative —
// the server recomputes the figure from the hotel's policy and ignores whatever
// is submitted here. The choice controls are PanelsUI primitives (RadioGroup,
// SelectMenu) that own their own markup, so we read them by field name rather
// than by per-control Stimulus targets.
export default class extends Controller {
  static targets = ["chargeSection", "checkoutSection", "policySection", "customSection", "displayAmount", "amountInput", "submitButton"]
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

  get chargeSource() {
    const checked = this.element.querySelector('input[name="charge_source"]:checked')
    if (checked) return checked.value

    const hidden = this.element.querySelector('input[type="hidden"][name="charge_source"]')
    return hidden ? hidden.value : "custom"
  }

  get hasPolicySection() {
    return this.hasPolicySectionTarget
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
      this.hidePolicySection()
      this.amountInputTarget.value = 0
      return
    }

    this.checkoutSectionTarget.classList.remove("hidden")

    if (this.resolution === "waive") {
      this.submitButtonTarget.textContent = "Approve without charge"
      this.submitButtonTarget.dataset.turboSubmitsWith = "Approving…"
      this.chargeSectionTarget.classList.add("hidden")
      this.customSectionTarget.classList.add("hidden")
      this.hidePolicySection()
      this.amountInputTarget.value = 0
      return
    }

    this.submitButtonTarget.textContent = "Approve and apply charges"
    this.submitButtonTarget.dataset.turboSubmitsWith = "Approving…"
    this.chargeSectionTarget.classList.remove("hidden")

    if (this.chargeSource === "policy" && this.hasPolicySection) {
      this.customSectionTarget.classList.add("hidden")
      this.policySectionTarget.classList.remove("hidden")
      this.amountInputTarget.value = this.baseAmountValue.toFixed(2)
    } else {
      this.customSectionTarget.classList.remove("hidden")
      this.hidePolicySection()
      this.updateCalculation()
    }
  }

  hidePolicySection() {
    if (this.hasPolicySection) this.policySectionTarget.classList.add("hidden")
  }

  updateCalculation() {
    if (this.resolution !== "charge") return
    if (this.chargeSource === "policy") return

    const adjustment = this.customType === "percentage" ? this.baseAmountValue * (this.customValue / 100) : this.customValue
    const finalAmount = this.baseAmountValue + adjustment

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
