import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "method", "amount", "preview", "baseTotal", "surchargeLabel", "surchargeTotal",
    "taxRow", "taxTotal", "collectedTotal"
  ]

  static values = { methods: Object, currency: String }

  connect() {
    this.update()
  }

  update() {
    const method = this.methodsValue[this.nativeSelectValue(this.methodTarget)]
    const base = Number.parseFloat(this.amountTarget.value || "0")
    if (!method || base <= 0) {
      this.previewTarget.hidden = true
      return
    }

    const surcharge = this.surchargeFor(method, base)
    const tax = (method.taxes || []).reduce((total, rule) => {
      const value = Number.parseFloat(rule.amount || "0")
      const lineAmount = rule.rate_type === "percentage" ? surcharge * value / 100 : value
      return total + this.money(lineAmount)
    }, 0)
    const roundedSurcharge = this.money(surcharge)
    const roundedTax = this.money(tax)
    const collected = this.money(base + roundedSurcharge + roundedTax)

    this.previewTarget.hidden = false
    this.baseTotalTarget.textContent = this.formatMoney(base)
    this.surchargeLabelTarget.textContent = method.name ? `${method.name} surcharge` : "Surcharge"
    this.surchargeTotalTarget.textContent = this.formatMoney(roundedSurcharge)
    this.taxRowTarget.hidden = roundedTax === 0
    this.taxTotalTarget.textContent = this.formatMoney(roundedTax)
    this.collectedTotalTarget.textContent = this.formatMoney(collected)
  }

  surchargeFor(method, base) {
    const value = Number.parseFloat(method.surcharge_value || "0")
    return method.surcharge_posting_type === "percentage" ? base * value / 100 : value
  }

  money(value) {
    return Math.round((value + Number.EPSILON) * 100) / 100
  }

  formatMoney(value) {
    return `${this.currencyValue} ${this.money(value).toFixed(2)}`
  }

  nativeSelectValue(target) {
    const select = target.matches("select") ? target : target.querySelector("select")
    return select?.value
  }
}
