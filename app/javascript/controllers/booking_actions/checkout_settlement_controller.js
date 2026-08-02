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
    "settlementFields",
    "settlementButton",
    "settlementButtonLabel",
    "settlementPaymentIcon",
    "settlementRefundIcon",
    "balanceAmount",
    "settlementLabel",
    "settlementControl",
    "settlementResolved",
    "actionOutcome",
    "pollStatus",
    "reasonFields",
    "directBillFields",
    "bookingRow",
    "selectedCount",
    "collectNowAmount",
    "directBillAmount",
    "keepOpenCount",
    "requiresSelection",
    "emptySelection",
    "depositRow",
    "depositBookingSection",
    "depositActionControl",
    "depositActionButton",
    "depositAvailable",
    "depositApplied",
    "depositReturned",
    "depositStatus"
  ]
  static values = {
    currency: { type: String, default: "MYR" },
    groupCheckout: { type: Boolean, default: false },
    statusUrl: String,
    pollInterval: { type: Number, default: 2000 }
  }

  connect() {
    this.connected = true
    this.selectedBookingIds = this.checkedBookingIds
    this.baseAmounts = this.snapshotAmounts()
    this.earlyDepartureAdjustments = {}
    this.earlyDepartureParams = {}
    this.poll = this.poll.bind(this)
    this.visibilityChanged = this.visibilityChanged.bind(this)
    document.addEventListener("visibilitychange", this.visibilityChanged)
    this.syncBookingRowVisibility()
    this.syncDepositSections()
    this.updateDepositActions()
    this.updateSettlementDetails()
    this.validate()
    if (this.hasStatusUrlValue) {
      this.pollTimer = window.setInterval(this.poll, this.pollIntervalValue)
      this.poll()
    }
  }

  disconnect() {
    this.connected = false
    document.removeEventListener("visibilitychange", this.visibilityChanged)
    if (this.pollTimer) window.clearInterval(this.pollTimer)
    this.pollAbortController?.abort()
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
      this.earlyDepartureAdjustments[folioId] = charge
      if (event.detail?.bookingId) {
        this.earlyDepartureParams[event.detail.bookingId] = {
          applyCharge: event.detail.applyCharge,
          type: event.detail.type,
          value: event.detail.value
        }
      }
      const input = this.element.querySelector(`input[name$="[${folioId}][amount]"]`)
      if (input) {
        const base = this.baseAmounts[folioId] || 0
        input.value = (base + charge).toFixed(2)
      }
      const row = this.folioRowTargets.find((target) => target.dataset.folioId === folioId)
      if (row) {
        this.applyFolioState(row, (this.baseAmounts[folioId] || 0) + charge, "open")
        const button = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementButton"]`)
        if (button) {
          button.removeAttribute("href")
          button.setAttribute("aria-disabled", "true")
        }
      }
    }

    this.updateFooterSummary()
    this.validate()
    if (this.polling) {
      this.pollAbortController?.abort()
      this.polling = false
    }
    this.poll()
  }

  validate() {
    if (!this.hasSubmitButtonTarget) return

    let valid = true
    if (this.hasFolioRowTarget) {
      valid = valid && this.visibleFolioRows.length > 0 && this.visibleRequiredFieldsComplete
      valid = valid && this.visibleFolioRows.every((row) => {
        const settlement = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementFields"]`)
        return !settlement || settlement.classList.contains("hidden")
      })
    }
    valid = valid && this.depositRowTargets.every((row) => {
      if (!this.depositRowVisible(row)) return true
      return row.dataset.blocking !== "true" || this.roundMoney(Number.parseFloat(row.dataset.availableAmount || "0")) === 0
    })

    this.submitButtonTarget.disabled = !valid
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !valid)
    this.submitButtonTarget.classList.toggle("opacity-50", !valid)
  }

  updateSettlementDetails() {
    this.folioRowTargets.forEach((row) => {
      const folioId = row.dataset.folioId
      const action = this.selectedActionFor(folioId)

      this.toggleFields(row, "reasonFields", [ "keep_open", "manager_review", "write_off_approval" ].includes(action))
      this.toggleFields(row, "directBillFields", action === "direct_bill")
      this.updateSettlementButton(row, action)
      this.updateActionOutcome(row, action)
    })
    this.updateFooterSummary()
    this.validate()
  }

  syncBookingSections(event) {
    this.selectedBookingIds = event.detail?.bookingIds || []
    this.syncBookingRowVisibility()
    this.syncDepositSections()
    this.updateDepositActionUrls()
    this.updateSettlementDetails()
    this.poll()
  }

  syncDepositSections() {
    this.depositBookingSectionTargets.forEach((section) => {
      section.classList.toggle("hidden", !this.selectedBookingIds.includes(section.dataset.bookingId) && !this.singleBookingMode)
    })
  }

  updateDepositActionUrls() {
    this.depositActionButtonTargets.forEach((button) => {
      const control = this.depositActionControlTargets.find((target) => target.dataset.depositId === button.dataset.depositId)
      const operation = control ? this.controlValue(control) : ""
      const source = operation === "apply" ? button.dataset.applyUrl : button.dataset.returnUrl
      if (!source) return

      const url = new URL(source, window.location.origin)
      url.searchParams.delete("booking_ids[]")
      this.selectedBookingIds.forEach((bookingId) => url.searchParams.append("booking_ids[]", bookingId))
      button.href = url.toString()
    })
  }

  updateDepositAction(event) {
    const control = event?.currentTarget || event?.target
    const depositId = control?.dataset.depositId
    const button = this.depositActionButtonTargets.find((target) => target.dataset.depositId === depositId)
    if (!button) return

    const operation = this.controlValue(control)
    button.href = operation === "apply" ? button.dataset.applyUrl : button.dataset.returnUrl
    const label = button.querySelector("[data-deposit-action-label]")
    if (label) label.textContent = this.humanizeAction(operation)
    this.updateDepositActionUrls()
  }

  updateDepositActions() {
    this.depositActionControlTargets.forEach((control) => this.updateDepositAction({ currentTarget: control }))
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

  async poll() {
    if (this.polling || document.visibilityState === "hidden") return

    this.polling = true
    const abortController = new AbortController()
    this.pollAbortController = abortController
    try {
      const statusUrl = new URL(this.statusUrlValue, window.location.origin)
      Object.entries(this.earlyDepartureParams).forEach(([bookingId, values]) => {
        statusUrl.searchParams.set(`early_departures[${bookingId}][apply_charge]`, values.applyCharge ? "1" : "0")
        statusUrl.searchParams.set(`early_departures[${bookingId}][type]`, values.type)
        statusUrl.searchParams.set(`early_departures[${bookingId}][value]`, values.value)
      })
      this.selectedBookingIds.forEach((bookingId) => statusUrl.searchParams.append("booking_ids[]", bookingId))
      const response = await fetch(statusUrl, {
        headers: { Accept: "application/json" },
        signal: abortController.signal
      })
      if (!response.ok) throw new Error("Folio balances could not be checked")

      const result = await response.json()
      if (!this.connected) return
      result.folios.forEach((folio) => {
        const id = String(folio.folio_id)
        const row = this.folioRowTargets.find((target) => target.dataset.folioId === id)
        if (!row) return

        const balance = Number.parseFloat(folio.balance) || 0
        this.baseAmounts[id] = balance - (this.earlyDepartureAdjustments[id] || 0)
        row.querySelectorAll(`[data-booking-actions--checkout-settlement-target~="settlementButton"]`).forEach((button) => {
          button.dataset.paymentUrl = folio.payment_url
          button.dataset.refundUrl = folio.refund_url
          button.removeAttribute("aria-disabled")
        })
        const input = this.element.querySelector(`input[name$="[${id}][amount]"]`)
        if (input) input.value = balance.toFixed(2)
        this.applyFolioState(row, balance, folio.status)
      })
      result.deposits.forEach((deposit) => this.applyDepositState(deposit))
      this.pollingErrorShown = false
      if (this.hasPollStatusTarget) this.pollStatusTarget.textContent = "Folio balances updated."
      this.updateFooterSummary()
      this.validate()
    } catch (error) {
      if (error.name === "AbortError") return
      if (!this.pollingErrorShown) {
        this.pollingErrorShown = true
        window.toast?.("Folio status unavailable", { type: "error", description: error.message })
      }
      if (this.hasPollStatusTarget) this.pollStatusTarget.textContent = error.message
    } finally {
      if (this.pollAbortController === abortController) {
        this.polling = false
        this.pollAbortController = null
      }
    }
  }

  visibilityChanged() {
    if (document.visibilityState === "visible") this.poll()
  }

  applyDepositState(deposit) {
    const row = this.depositRowTargets.find((target) => target.dataset.depositId === String(deposit.deposit_id))
    if (!row) return

    const available = Number.parseFloat(deposit.available_amount) || 0
    row.dataset.availableAmount = available.toFixed(2)
    row.dataset.blocking = deposit.blocking ? "true" : "false"
    const currency = row.querySelector(`[data-booking-actions--checkout-settlement-target~="depositAvailable"]`)?.textContent.trim().split(" ")[0] || this.currencyValue
    const setMoney = (targetName, value) => {
      const target = row.querySelector(`[data-booking-actions--checkout-settlement-target~="${targetName}"]`)
      if (target) target.textContent = `${currency} ${this.formatMoney(Number.parseFloat(value) || 0)}`
    }
    setMoney("depositApplied", deposit.applied_amount)
    setMoney("depositReturned", deposit.returned_amount)
    setMoney("depositAvailable", deposit.available_amount)
    const status = row.querySelector(`[data-booking-actions--checkout-settlement-target~="depositStatus"]`)
    if (status) status.textContent = this.humanizeAction(deposit.status)

    const resolved = this.roundMoney(available) === 0
    row.querySelector("[data-deposit-settlement-control]")?.classList.toggle("hidden", resolved)
    row.querySelector("[data-deposit-resolved]")?.classList.toggle("hidden", !resolved)
    const button = row.querySelector(`[data-booking-actions--checkout-settlement-target~="depositActionButton"]`)
    button?.classList.toggle("hidden", resolved)
    row.querySelector("[data-deposit-action-complete]")?.classList.toggle("hidden", !resolved)
  }

  applyFolioState(row, balance, status) {
    const amount = row.querySelector(`[data-booking-actions--checkout-settlement-target~="balanceAmount"]`)
    if (amount) amount.textContent = `${this.currencyValue} ${this.formatMoney(balance)}`

    const action = this.selectedActionFor(row.dataset.folioId)
    this.updateSettlementDisplay(row, action, balance, status)
    this.updateSettlementButton(row, action, balance, status)
    this.updateActionOutcome(row, action, balance, status)
  }

  updateSettlementDisplay(row, action, balance, status) {
    const settled = status === "closed" || this.roundMoney(balance) === 0
    const label = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementLabel"]`)
    const control = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementControl"]`)
    const resolved = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementResolved"]`)

    if (control) control.classList.toggle("hidden", settled)
    if (resolved) {
      resolved.classList.toggle("hidden", !settled)
      resolved.textContent = status === "closed" ? "Closed" : "Close"
    }
    if (label) {
      if (status === "closed") label.textContent = "Closed"
      else if (settled) label.textContent = "Close"
      else if (row.dataset.folioKind === "guest") label.textContent = balance > 0 ? "Pay now" : "Refund"
      else label.textContent = this.humanizeAction(action)
    }
  }

  updateSettlementButton(row, action, currentBalance = null, status = "open") {
    const container = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementFields"]`)
    const button = row.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementButton"]`)
    if (!container || !button) return

    const input = this.element.querySelector(`input[name$="[${row.dataset.folioId}][amount]"]`)
    const balance = currentBalance ?? (Number.parseFloat(input?.value || "0") || 0)
    const guest = row.dataset.folioKind === "guest"
    const payment = balance > 0 && (guest || action === "pay_now")
    const refund = balance < 0 && (guest || action === "refund_credit_handling")
    const visible = status === "open" && (payment || refund)
    container.classList.toggle("hidden", !visible)
    if (!visible) return

    button.href = payment ? button.dataset.paymentUrl : button.dataset.refundUrl
    button.dataset.variant = refund ? "warning" : "primary"
    button.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementPaymentIcon"]`)?.classList.toggle("hidden", refund)
    button.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementRefundIcon"]`)?.classList.toggle("hidden", !refund)
    const label = button.querySelector(`[data-booking-actions--checkout-settlement-target~="settlementButtonLabel"]`)
    if (label) label.textContent = `${refund ? "Refund" : "Pay"} ${this.currencyValue} ${this.formatMoney(Math.abs(balance))}`
  }

  updateActionOutcome(row, action, currentBalance = null, status = "open") {
    const outcome = row.querySelector(`[data-booking-actions--checkout-settlement-target~="actionOutcome"]`)
    if (!outcome) return

    const input = this.element.querySelector(`input[name$="[${row.dataset.folioId}][amount]"]`)
    const balance = currentBalance ?? (Number.parseFloat(input?.value || "0") || 0)
    const externalSettlement = balance !== 0 && (action === "pay_now" || action === "refund_credit_handling" || row.dataset.folioKind === "guest")
    const labels = {
      direct_bill: "Invoice to holder",
      keep_open: "Remains open",
      manager_review: "Send for review",
      write_off_approval: "Request approval",
      voided: "Resolve voided folio"
    }

    if (status === "closed") outcome.textContent = "Already closed"
    else if (this.roundMoney(balance) === 0) outcome.textContent = "Closes at checkout"
    else outcome.textContent = labels[action] || this.humanizeAction(action)
    outcome.classList.toggle("hidden", externalSettlement)
  }

  humanizeAction(action) {
    if (!action) return ""
    const value = action.replaceAll("_", " ")
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  amountForActionControl(control) {
    const input = this.element.querySelector(`input[name$="[${control.dataset.folioId}][amount]"]`)
    return this.roundMoney(Math.abs(Number.parseFloat(input?.value || "0")))
  }

  controlValue(control) {
    if (control.matches("input")) return control.value
    return control.matches("select") ? control.value : (control.querySelector("select")?.value || "")
  }

  rowBookingVisible(row) {
    if (!row) return false
    let selected = this.selectedBookingIds
    if (selected.length === 0) selected = this.checkedBookingIds
    return selected.includes(row.dataset.bookingId) || (selected.length === 0 && this.singleBookingMode)
  }

  depositRowVisible(row) {
    return !row.dataset.bookingId || this.selectedBookingIds.includes(row.dataset.bookingId) || this.singleBookingMode
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
