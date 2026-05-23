import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chargeSection", "customSection", "toggleRadio", "typeRadio", "customType", "customValue", "displayAmount", "amountInput"]
  static values = {
    baseAmount: Number,
    currency: { type: String, default: "MYR" }
  }

  connect() {
    this.updateUI()
  }

  updateUI() {
    const chargeToggle = this.toggleRadioTargets.find(r => r.checked).value
    
    if (chargeToggle === "none") {
      this.chargeSectionTarget.classList.add("hidden")
      this.customSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = 0
      return
    }

    this.chargeSectionTarget.classList.remove("hidden")
    const selectedType = this.typeRadioTargets.find(r => r.checked).value
    
    if (selectedType === "custom") {
      this.customSectionTarget.classList.remove("hidden")
      this.updateCalculation()
    } else {
      this.customSectionTarget.classList.add("hidden")
      this.amountInputTarget.value = this.baseAmountValue.toFixed(2)
    }
  }

  updateCalculation() {
    const chargeToggle = this.toggleRadioTargets.find(r => r.checked).value
    if (chargeToggle === "none") return

    const selectedType = this.typeRadioTargets.find(r => r.checked).value
    const type = this.customTypeTarget.value
    const value = parseFloat(this.customValueTarget.value) || 0
    let finalAmount = this.baseAmountValue

    if (selectedType === "custom") {
      let adjustment = 0
      if (type === "percentage") {
        adjustment = this.baseAmountValue * (value / 100)
      } else {
        adjustment = value
      }
      finalAmount += adjustment
    }

    this.amountInputTarget.value = finalAmount.toFixed(2)
    this.displayAmountTarget.textContent = `${this.currencyValue} ${finalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
}
