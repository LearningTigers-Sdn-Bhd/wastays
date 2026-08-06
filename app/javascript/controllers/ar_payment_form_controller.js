import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["account", "amount", "allocation", "amountSummary", "allocatedSummary", "unappliedSummary"]
  static values = { invoicesUrl: String }

  connect() {
    this.recalculate()
  }

  accountChanged() {
    const frame = document.getElementById("ar_payment_invoice_allocations")
    if (!frame || !this.hasInvoicesUrlValue) return

    const url = new URL(this.invoicesUrlValue, window.location.origin)
    url.searchParams.set("hotel_corporate_account_id", this.accountTarget.value)
    frame.src = url.toString()
  }

  recalculate() {
    if (!this.hasAmountSummaryTarget) return

    const amount = this.hasAmountTarget ? this.number(this.amountTarget.value) : 0
    const allocated = this.allocationTargets.reduce((total, input) => total + this.number(input.value), 0)
    const currency = this.amountSummaryTarget.closest("[data-currency]")?.dataset.currency || ""

    this.amountSummaryTarget.textContent = this.money(currency, amount)
    this.allocatedSummaryTarget.textContent = this.money(currency, allocated)
    this.unappliedSummaryTarget.textContent = this.money(currency, amount - allocated)
    this.unappliedSummaryTarget.classList.toggle("text-red-700", allocated > amount)
  }

  number(value) {
    const parsed = Number.parseFloat(value)
    return Number.isFinite(parsed) ? parsed : 0
  }

  money(currency, amount) {
    return `${currency} ${amount.toFixed(2)}`
  }
}
