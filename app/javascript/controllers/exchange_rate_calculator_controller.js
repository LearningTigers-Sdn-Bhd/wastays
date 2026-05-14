import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["baseCurrency", "targetCurrency", "rate", "calculation", "baseLabel", "targetLabel", "curr1", "curr2", "forwardRate", "inverseRate"]

  connect() {
    this.update()
  }

  update() {
    const base = (this.baseCurrencyTarget.value || "MYR").toUpperCase()
    const target = (this.targetCurrencyTarget.value || "USD").toUpperCase()
    const rate = parseFloat(this.rateTarget.value)

    // Update labels
    this.baseLabelTargets.forEach(el => el.textContent = base)
    this.targetLabelTargets.forEach(el => el.textContent = target)
    this.curr1Target.textContent = base
    this.curr2Target.textContent = target

    if (base && target && base !== target && !isNaN(rate) && rate > 0) {
      this.calculationTarget.classList.remove("hidden")
      
      // Forward rate: 1 BASE = rate TARGET
      this.forwardRateTarget.textContent = rate.toLocaleString(undefined, { minimumFractionDigits: 4, maximumFractionDigits: 8 })
      
      // Inverse rate: 1 TARGET = (1/rate) BASE
      const inverse = 1 / rate
      this.inverseRateTarget.textContent = inverse.toLocaleString(undefined, { minimumFractionDigits: 4, maximumFractionDigits: 8 })
    } else {
      this.calculationTarget.classList.add("hidden")
    }
  }
}
