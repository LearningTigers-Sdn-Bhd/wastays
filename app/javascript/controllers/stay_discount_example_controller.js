import { Controller } from "@hotwired/stimulus"
import { renderStayDiscountExample, stayDiscountExample } from "lib/stay_discount_example"

// Worked example under a long-stay discount rule, recalculated as the rule is
// edited. See lib/stay_discount_example for the math (shared with the "Add
// discount" wizard's step-3 simulator).
export default class extends Controller {
  static targets = ["minNights", "discountType", "value", "fromNight", "unit", "heading", "body"]
  static values = { price: Number, currency: String, perPerson: Boolean }

  connect() {
    // A row cloned from the template carries the price it was rendered with,
    // which may be stale by now; the section holds the current one.
    const section = this.element.closest("[data-stay-discount-wizard-price-value]")
    const current = Number.parseFloat(section?.dataset.stayDiscountWizardPriceValue)
    if (current > 0) this.priceValue = current
    this.render()
  }

  updatePrice(event) {
    this.priceValue = event.detail.price
    this.render()
  }

  render() {
    const percent = this.discountTypeTarget.value !== "amount"
    this.unitTarget.textContent = percent ? "%" : this.currencyValue

    const example = stayDiscountExample({
      nights: Number.parseInt(this.minNightsTarget.value, 10),
      percent,
      value: Number.parseFloat(this.valueTarget.value),
      fromNight: Number.parseInt(this.fromNightTarget.value, 10) || 1,
      price: this.priceValue,
      currency: this.currencyValue,
      perPerson: this.perPersonValue
    })

    renderStayDiscountExample(example, { heading: this.headingTarget, body: this.bodyTarget })
  }
}
