import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "submitButton",
    "actionSelect",
    "detailRow",
    "paymentFields",
    "reasonFields",
    "directBillFields",
    "bookingRow",
    "selectedCount",
    "collectNowAmount",
    "directBillAmount",
    "keepOpenCount",
    "requiresSelection",
    "emptySelection"
  ]
  static values = {
    currency: { type: String, default: "MYR" },
    groupCheckout: { type: Boolean, default: false }
  }

  connect() {
    this.selectedBookingIds = this.checkedBookingIds
    this.syncBookingRowVisibility()
    this.updateSettlementDetails()
    this.validate()
  }

  updateEarlyDepartureCharge() {
    this.validate()
  }

  validate() {
    if (!this.hasSubmitButtonTarget) {
      return
    }

    let valid = true
    if (this.hasBookingRowTarget) {
      valid = valid && this.visibleBookingRows.length > 0 && this.visibleRequiredFieldsComplete
    }

    this.submitButtonTarget.disabled = !valid
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !valid)
    this.submitButtonTarget.classList.toggle("opacity-50", !valid)
    this.submitButtonTarget.classList.toggle("hover:bg-slate-700", valid)
  }

  updateSettlementDetails() {
    this.detailRowTargets.forEach((row) => {
      const folioId = row.dataset.folioId
      const action = this.selectedActionFor(folioId)
      const bookingVisible = this.rowBookingVisible(row)
      const visible = bookingVisible && ["pay_now", "direct_bill", "keep_open", "manager_review", "write_off_approval"].includes(action)

      row.classList.toggle("hidden", !visible)
      this.toggleFields(row, "paymentFields", action === "pay_now")
      this.toggleFields(row, "reasonFields", ["keep_open", "manager_review", "write_off_approval"].includes(action))
      this.toggleFields(row, "directBillFields", action === "direct_bill")
    })
    this.updateFooterSummary()
    this.validate()
  }

  syncBookingSections(event) {
    this.selectedBookingIds = event.detail?.bookingIds || []
    this.syncBookingRowVisibility()
    this.updateSettlementDetails()
  }

  syncBookingRowVisibility() {
    if (!this.hasBookingRowTarget) return

    let selected = this.selectedBookingIds
    if (selected.length === 0) selected = this.checkedBookingIds
    const emptyGroupSelection = this.groupCheckoutValue && selected.length === 0

    this.bookingRowTargets.forEach((row) => {
      const visible = !emptyGroupSelection && (selected.includes(row.dataset.bookingId) || (selected.length === 0 && this.singleBookingMode))
      row.classList.toggle("hidden", !visible)
      row.querySelectorAll("input, select, textarea").forEach((field) => {
        if (field.name?.startsWith("checkout_bookings") || field.name?.startsWith("early_departures")) field.disabled = !visible
      })
    })

    this.toggleEmptySelection(emptyGroupSelection)
  }

  toggleEmptySelection(empty) {
    this.requiresSelectionTargets.forEach((target) => target.classList.toggle("hidden", empty))
    if (this.hasEmptySelectionTarget) {
      this.emptySelectionTarget.classList.toggle("hidden", !empty)
      this.emptySelectionTarget.classList.toggle("flex", empty)
    }
  }

  updateFooterSummary() {
    if (this.hasSelectedCountTarget) {
      const count = this.visibleBookingIds.length
      this.selectedCountTarget.textContent = count === 0 && this.groupCheckoutValue ? "Please select bookings" : `${count} ${count === 1 ? "booking" : "bookings"}`
    }

    let collectNow = 0
    let directBill = 0
    let keepOpen = 0

    this.actionSelectTargets.forEach((select) => {
      if (!this.rowBookingVisible(select.closest("[data-checkout-settlement-target~='bookingRow']"))) return

      const amount = this.amountForActionSelect(select)
      if (select.value === "pay_now") collectNow += amount
      if (select.value === "direct_bill") directBill += amount
      if (["keep_open", "manager_review", "write_off_approval"].includes(select.value)) keepOpen += 1
    })

    if (this.hasCollectNowAmountTarget) this.collectNowAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(collectNow)}`
    if (this.hasDirectBillAmountTarget) this.directBillAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(directBill)}`
    if (this.hasKeepOpenCountTarget) this.keepOpenCountTarget.textContent = `${keepOpen} ${keepOpen === 1 ? "folio" : "folios"}`
  }

  selectedActionFor(folioId) {
    const select = this.actionSelectTargets.find((target) => target.dataset.folioId === folioId)
    return select ? select.value : ""
  }

  toggleFields(row, targetName, enabled) {
    row.querySelectorAll(`[data-checkout-settlement-target='${targetName}']`).forEach((container) => {
      container.classList.toggle("hidden", !enabled)
      container.querySelectorAll("input, select, textarea").forEach((input) => {
        if (input.dataset.requiredForAction === "true") {
          input.required = enabled
        }
      })
    })
  }

  amountForActionSelect(select) {
    const input = this.element.querySelector(`input[name$="[${select.dataset.folioId}][amount]"]`)
    return this.roundMoney(Math.abs(Number.parseFloat(input?.value || "0")))
  }

  rowBookingVisible(row) {
    if (!row) return false
    let selected = this.selectedBookingIds
    if (selected.length === 0) selected = this.checkedBookingIds
    return selected.includes(row.dataset.bookingId) || (selected.length === 0 && this.singleBookingMode)
  }

  get checkedBookingIds() {
    return Array.from(this.element.querySelectorAll("input[name='booking_ids[]']:checked")).map((input) => input.dataset.bookingId || input.value)
  }

  get visibleBookingRows() {
    return this.hasBookingRowTarget ? this.bookingRowTargets.filter((row) => !row.classList.contains("hidden")) : []
  }

  get visibleBookingIds() {
    return [...new Set(this.visibleBookingRows.map((row) => row.dataset.bookingId).filter(Boolean))]
  }

  get visibleRequiredFieldsComplete() {
    return this.visibleBookingRows.every((row) => {
      return Array.from(row.querySelectorAll("input[required], select[required], textarea[required]")).every((field) => field.disabled || field.value.trim() !== "")
    })
  }

  get singleBookingMode() {
    return !this.groupCheckoutValue && this.checkedBookingIds.length === 0
  }

  formatMoney(value) {
    return this.roundMoney(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }

  roundMoney(value) {
    return Math.round((Number.isFinite(value) ? value : 0) * 100) / 100
  }
}
