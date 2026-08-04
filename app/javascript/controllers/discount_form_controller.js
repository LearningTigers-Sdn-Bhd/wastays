import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["code", "pricingType", "scope", "rateField", "ratePrefix", "selectedCodesField", "overrideField"]
  static values = { currency: String }

  connect() { this.update() }

  formatCode() {
    this.codeTarget.value = this.codeTarget.value.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/_+/g, "_").replace(/^_+|_+$/g, "").slice(0, 10)
  }

  update() {
    const pricing = this.valueOf(this.pricingTypeTarget) || "manual"
    const scope = this.valueOf(this.scopeTarget) || "all_eligible_charges"
    this.rateFieldTarget.hidden = pricing === "manual"
    this.ratePrefixTarget.textContent = pricing === "percentage" ? "%" : this.currencyValue
    this.selectedCodesFieldTarget.hidden = scope !== "selected_charges"
    const codeSelect = this.selectedCodesFieldTarget.querySelector("select")
    if (codeSelect) codeSelect.required = scope === "selected_charges"
    this.overrideFieldTarget.hidden = pricing !== "fixed"
  }

  valueOf(target) {
    return (target.matches("select") ? target : target.querySelector("select"))?.value
  }
}
