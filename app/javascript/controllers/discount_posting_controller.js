import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["discount", "amount", "postingDate", "fingerprint", "preview", "baseTotal", "discountTotal", "error"]
  static values = { discounts: Object, quoteUrl: String, currency: String }

  connect() { this.sequence = 0; this.update() }

  async update() {
    const id = this.valueOf(this.discountTarget)
    const discount = this.discountsValue[id]
    if (!discount || !this.postingDateTarget.value) { this.previewTarget.hidden = true; return }

    const sequence = ++this.sequence
    this.previewTarget.hidden = false
    this.previewTarget.setAttribute("aria-busy", "true")
    const url = new URL(this.quoteUrlValue, window.location.origin)
    url.searchParams.set("hotel_discount_id", id)
    url.searchParams.set("booking_folio_id", this.folioId())
    url.searchParams.set("posting_date", this.postingDateTarget.value)
    url.searchParams.set("amount", this.amountTarget.value)

    const response = await fetch(url, { headers: { Accept: "application/json" } })
    const payload = await response.json()
    if (sequence !== this.sequence) return

    this.previewTarget.setAttribute("aria-busy", "false")
    this.errorTarget.hidden = response.ok
    this.errorTarget.textContent = payload.error || "Discount could not be calculated."
    this.baseTotalTarget.textContent = this.money(payload.base_amount)
    this.discountTotalTarget.textContent = this.money(payload.amount)
    this.fingerprintTarget.value = payload.fingerprint || ""

    const calculated = Number.parseFloat(payload.calculated_amount || "0")
    if (response.ok && discount.pricing_type !== "manual" && (!this.amountTarget.value || !discount.allow_amount_override)) this.amountTarget.value = calculated.toFixed(2)
    this.amountTarget.readOnly = discount.pricing_type !== "manual" && !discount.allow_amount_override
  }

  folioId() {
    return this.element.querySelector("[name='folio_transaction[booking_folio_id]']")?.value || ""
  }

  valueOf(target) { return (target.matches("select") ? target : target.querySelector("select"))?.value }
  money(value) { return `${this.currencyValue} ${Number.parseFloat(value || "0").toFixed(2)}` }
}
