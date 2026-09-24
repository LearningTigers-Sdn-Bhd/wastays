import { Controller } from "@hotwired/stimulus"

// Worked example under a long-stay discount rule, recalculated as the rule is
// edited. Mirrors RatePlanStayDiscount#apply: percent or a fixed amount off
// each discounted night, never below zero, rounded to cents.
export default class extends Controller {
  static targets = ["minNights", "discountType", "value", "fromNight", "unit", "heading", "lines"]
  static values = { price: Number, currency: String, perPerson: Boolean }

  connect() {
    this.render()
  }

  render() {
    const percent = this.discountTypeTarget.value !== "amount"
    this.unitTarget.textContent = percent ? "%" : this.currencyValue

    const nights = parseInt(this.minNightsTarget.value, 10)
    const value = parseFloat(this.valueTarget.value)
    const fromNight = Math.min(parseInt(this.fromNightTarget.value, 10) || 1, nights || 1)
    if (!(nights >= 2) || !(value > 0) || (percent && value > 100)) {
      return this.show("Example", ["Enter the nights and the discount to see an example."])
    }

    const price = this.priceValue
    const discounted = this.round(Math.max(percent ? price * (1 - value / 100) : price - value, 0))
    const fullNights = fromNight - 1
    const discountedNights = nights - fullNights
    const normalTotal = price * nights
    const total = price * fullNights + discounted * discountedNights

    const guest = this.perPersonValue ? " for 1 guest" : ""
    const lines = []
    if (fullNights > 0) lines.push(`${this.range(1, fullNights)}: ${this.money(price)} (normal price)`)
    lines.push(`${this.range(fromNight, nights)}: ${this.money(price)} → ${this.money(discounted)}`)
    lines.push(`Total: ${this.money(normalTotal)} → ${this.money(total)} (guest saves ${this.money(normalTotal - total)})`)

    this.show(`Example: a ${nights}-night stay${guest} at ${this.money(price)} a night`, lines)
  }

  show(heading, lines) {
    this.headingTarget.textContent = heading
    this.linesTarget.replaceChildren(...lines.map((line) => {
      const item = document.createElement("li")
      item.textContent = line
      return item
    }))
  }

  range(first, last) {
    return first === last ? `Night ${first}` : `Nights ${first}–${last}`
  }

  round(amount) {
    return Math.round(amount * 100) / 100
  }

  money(amount) {
    const rounded = this.round(amount)
    const digits = Number.isInteger(rounded) ? 0 : 2
    return `${this.currencyValue} ${rounded.toLocaleString("en", { minimumFractionDigits: digits, maximumFractionDigits: 2 })}`
  }
}
