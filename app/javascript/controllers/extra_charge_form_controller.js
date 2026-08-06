import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "name", "code", "pricingType", "pricedFields", "percentageFields", "unitFields",
    "overrideFields", "rate", "ratePrefix", "previewName", "previewAmount"
  ]

  static values = { currency: String }

  connect() {
    this.update()
  }

  formatCode() {
    this.codeTarget.value = this.codeTarget.value
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 10)
  }

  update() {
    const pricingType = this.nativeSelectValue(this.pricingTypeTarget) || "manual"
    const manual = pricingType === "manual"
    const fixed = pricingType === "fixed"
    const percentage = pricingType === "percentage"

    this.pricedFieldsTarget.hidden = manual
    this.percentageFieldsTarget.hidden = !percentage
    this.unitFieldsTarget.hidden = percentage
    this.overrideFieldsTarget.hidden = !fixed
    this.ratePrefixTarget.textContent = percentage ? "%" : this.currencyValue
    this.previewNameTarget.textContent = this.nameTarget.value.trim() || "Extra charge"

    const rate = Number.parseFloat(this.rateTarget.value || "0")
    if (manual) {
      this.previewAmountTarget.textContent = "Staff enters amount"
    } else if (percentage) {
      this.previewAmountTarget.textContent = rate > 0 ? `${rate.toFixed(2)}% of selected basis` : "Enter percentage"
    } else {
      this.previewAmountTarget.textContent = rate > 0 ? `${this.currencyValue} ${rate.toFixed(2)}` : "Enter price"
    }
  }

  nativeSelectValue(target) {
    const select = target.matches("select") ? target : target.querySelector("select")
    return select?.value
  }
}
