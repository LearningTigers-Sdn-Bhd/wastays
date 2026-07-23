import { Controller } from "@hotwired/stimulus"

// Checkout settlement coordinator for the checkout Sheet (booking-actions
// namespace, isolated from the legacy implementation). Shows/hides per-folio
// settlement inputs, keeps the footer totals live, gates the submit button, and
// folds the manual early-departure charge into the folio it routes to so the
// pay-now amount matches the post-early-departure balance.
export default class extends Controller {
  static targets = [
    "submitButton",
    "actionControl",
    "folioRow",
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
    this.baseAmounts = this.snapshotAmounts()
    this.syncBookingRowVisibility()
    this.updateSettlementDetails()
    this.validate()
  }

  // Snapshot each folio's server-rendered amount so a live early-departure
  // charge can be added on top without compounding across events.
  snapshotAmounts() {
    const amounts = {}
    this.element.querySelectorAll("input[name$='[amount]']").forEach((input) => {
      const match = input.name.match(/\[(\d+)\]\[amount\]$/)
      if (match) amounts[match[1]] = parseFloat(input.value || "0") || 0
    })
    return amounts
  }

  updateEarlyDepartureCharge(event) {
    const folioId = event.detail?.targetFolioId
    const charge = Number(event.detail?.amount) || 0

    if (folioId) {
      const input = this.element.querySelector(`input[name$="[${folioId}][amount]"]`)
      if (input) {
        const base = this.baseAmounts[folioId] || 0
        input.value = (base + charge).toFixed(2)
      }
    }

    this.updateFooterSummary()
    this.validate()
  }

  validate() {
    if (!this.hasSubmitButtonTarget) return

    let valid = true
    if (this.hasFolioRowTarget) {
      valid = valid && this.visibleFolioRows.length > 0 && this.visibleRequiredFieldsComplete
    }

    this.submitButtonTarget.disabled = !valid
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !valid)
    this.submitButtonTarget.classList.toggle("opacity-50", !valid)
  }

  updateSettlementDetails() {
    this.folioRowTargets.forEach((row) => {
      const folioId = row.dataset.folioId
      const action = this.selectedActionFor(folioId)

      this.toggleFields(row, "paymentFields", action === "pay_now")
      this.toggleFields(row, "reasonFields", [ "keep_open", "manager_review", "write_off_approval" ].includes(action))
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
      row.querySelectorAll("input, select, textarea, button").forEach((field) => {
        if (!field.name?.startsWith("checkout_bookings") && !field.name?.startsWith("early_departures") && field.tagName !== "BUTTON") return

        const permanentlyDisabled = field.closest("[data-permanent-disabled='true']") !== null
        field.disabled = !visible || permanentlyDisabled
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

    this.actionControlTargets.forEach((control) => {
      if (!this.rowBookingVisible(control.closest("[data-booking-actions--checkout-settlement-target~='bookingRow']"))) return

      const action = this.controlValue(control)
      const amount = this.amountForActionControl(control)
      if (action === "pay_now") collectNow += amount
      if (action === "direct_bill") directBill += amount
      if ([ "keep_open", "manager_review", "write_off_approval" ].includes(action)) keepOpen += 1
    })

    if (this.hasCollectNowAmountTarget) this.collectNowAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(collectNow)}`
    if (this.hasDirectBillAmountTarget) this.directBillAmountTarget.textContent = `${this.currencyValue} ${this.formatMoney(directBill)}`
    if (this.hasKeepOpenCountTarget) this.keepOpenCountTarget.textContent = `${keepOpen} ${keepOpen === 1 ? "folio" : "folios"}`
  }

  selectedActionFor(folioId) {
    const control = this.actionControlTargets.find((target) => target.dataset.folioId === folioId)
    return control ? this.controlValue(control) : ""
  }

  toggleFields(row, targetName, enabled) {
    row.querySelectorAll(`[data-booking-actions--checkout-settlement-target='${targetName}']`).forEach((container) => {
      container.classList.toggle("hidden", !enabled)
      container.querySelectorAll("[data-conditional-required='true'] input, [data-conditional-required='true'] select, [data-required-for-action='true']").forEach((input) => {
        input.required = enabled
      })
    })
  }

  amountForActionControl(control) {
    const input = this.element.querySelector(`input[name$="[${control.dataset.folioId}][amount]"]`)
    return this.roundMoney(Math.abs(Number.parseFloat(input?.value || "0")))
  }

  controlValue(control) {
    return control.matches("select") ? control.value : (control.querySelector("select")?.value || "")
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

  get visibleFolioRows() {
    return this.hasFolioRowTarget ? this.folioRowTargets.filter((row) => !row.classList.contains("hidden")) : []
  }

  get visibleBookingIds() {
    return [ ...new Set(this.visibleBookingRows.map((row) => row.dataset.bookingId).filter(Boolean)) ]
  }

  get visibleRequiredFieldsComplete() {
    return this.visibleFolioRows.every((row) => {
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
