import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["customFields", "percentage", "amount", "summary", "variance", "outcome"]
  static values = { otaAmount: Number, expectedAmount: Number, roomNights: Number, currency: String }

  connect() {
    this.refreshPreview()
  }

  policyChanged() {
    const custom = this.mode === "custom"
    this.customFieldsTarget.classList.toggle("hidden", !custom)
    this.customFieldsTarget.setAttribute("aria-hidden", custom ? "false" : "true")
    this.refreshPreview()
  }

  refreshPreview() {
    const difference = Math.abs(this.otaAmountValue - this.expectedAmountValue)
    const percentage = this.expectedAmountValue === 0 ? 0 : (difference / this.expectedAmountValue) * 100
    const perRoomNight = difference / Math.max(this.roomNightsValue, 1)
    const needsReview = this.mode === "strict"
      ? difference > 0
      : percentage > this.percentageLimit || perRoomNight > this.amountLimit

    this.varianceTarget.textContent = `${this.currencyValue} ${difference.toFixed(2)} (${percentage.toFixed(2)}%)`
    this.outcomeTarget.textContent = needsReview ? "Booking ingested · rate review added" : "Booking ingested · no rate review"
    this.outcomeTarget.className = needsReview
      ? "mt-1 text-sm font-medium text-warning-foreground"
      : "mt-1 text-sm font-medium text-success-foreground"
    this.summaryTarget.textContent = this.summary
  }

  get mode() {
    return this.element.querySelector("input[name='ota_financial_settings[mode]']:checked")?.value || "recommended"
  }

  get percentageLimit() {
    if (this.mode === "strict") return 0
    if (this.mode === "recommended") return 1
    return this.hasPercentageTarget ? Number(this.percentageTarget.value || 0) : 0
  }

  get amountLimit() {
    if (this.mode === "strict") return 0
    if (this.mode === "recommended") return 10
    return this.hasAmountTarget ? Number(this.amountTarget.value || 0) : 0
  }

  get summary() {
    if (this.mode === "strict") return "Every non-zero rate difference is added to rate review."
    return `Differences above ${this.percentageLimit.toFixed(2).replace(/\.00$/, "")}% or ${this.currencyValue} ${this.amountLimit.toFixed(2)} per room-night are added to rate review.`
  }
}
