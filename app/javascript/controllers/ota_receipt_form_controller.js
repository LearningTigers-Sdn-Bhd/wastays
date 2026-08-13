import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "allocation", "allocated", "amount", "empty", "errorSummary", "remaining", "row", "search", "warning"
  ]

  static values = { currency: String }

  connect() {
    this.filter()
    this.updateTotals()

    if (this.hasErrorSummaryTarget) {
      requestAnimationFrame(() => this.errorSummaryTarget.focus())
    }
  }

  criteriaChanged(event) {
    const select = event.target.closest("select")
    if (!select) return

    const url = new URL(window.location.href)
    const key = select.name.endsWith("[booking_source_id]") ? "booking_source_id" : "currency"
    url.searchParams.set(key, select.value)
    if (key === "booking_source_id") url.searchParams.delete("currency")
    url.searchParams.delete("allocation_search")
    window.location.assign(url.toString())
  }

  scopeSearch(event) {
    event.preventDefault()
    const url = new URL(window.location.href)
    const query = this.searchTarget.value.trim()
    if (query) url.searchParams.set("allocation_search", query)
    else url.searchParams.delete("allocation_search")
    window.location.assign(url.toString())
  }

  filter() {
    if (!this.hasSearchTarget) return

    const query = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = query.length > 0 && !row.dataset.searchText.includes(query)
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.rowTargets.some((row) => !row.hidden)
    }
  }

  updateTotals() {
    const allocated = this.allocationTargets.reduce((total, input) => total + this.numberValue(input.value), 0)
    const receipt = this.hasAmountTarget ? this.numberValue(this.amountTarget.value) : 0
    const remaining = receipt - allocated

    this.setMetric(this.allocatedTarget, allocated)
    this.setMetric(this.remainingTarget, remaining)

    const overpaid = this.allocationTargets.some((input) => {
      return this.numberValue(input.value) > this.numberValue(input.dataset.outstanding)
    })
    if (this.hasWarningTarget) this.warningTarget.hidden = !overpaid
  }

  setMetric(card, amount) {
    const value = card.querySelector(".panel-metric-card__value")
    if (value) value.textContent = `${this.currencyValue} ${amount.toFixed(2)}`
  }

  numberValue(value) {
    const number = Number.parseFloat(value)
    return Number.isFinite(number) ? number : 0
  }
}
