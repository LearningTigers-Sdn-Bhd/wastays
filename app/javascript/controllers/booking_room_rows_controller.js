import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "rows", "row", "checkIn", "checkOut", "nights", "bookingType", "backdateFields", "corporate", "guestCountry",
    // Collection switches.
    "tourismTaxCollection", "depositCollection", "collectPayment", "tourismTaxCollected", "depositEnabled", "depositAmount",
    // Billing summary rows.
    "folioGroup", "folioNote", "roomTotal", "taxTotal", "tourismTaxRow", "tourismTaxTotal", "tourismTaxNote",
    "surchargeRow", "surchargeTotal", "surchargeTaxRow", "surchargeTaxTotal", "depositRow", "depositTotal",
    "collectedLabel", "collectedTotal", "grandTotal"
  ]
  static values = { availabilityUrl: String, rateOptionsUrl: String, priceUrl: String, roomRowUrl: String, autoAssignEnabled: Boolean }

  connect() {
    this.nextIndex = this.rowTargets.length
    this.baseTotal = 0
    this.tourismTax = 0
    this.surcharge = 0
    this.surchargeTax = 0
    this.onQuoteChanged = this.onQuoteChanged.bind(this)
    this.overrideTimeouts = new Map()
    window.addEventListener("booking:quote-changed", this.onQuoteChanged)
    if (this.rowTargets.length === 0) {
      this.add()
    } else {
      // Server-rendered rows: repopulate rate/room for any pre-filled row.
      this.rowTargets.forEach((row) => {
        if (this.readValue(this.roleEl(row, "room-type"))) {
          this.loadRow(row, { rate_plan_id: row.dataset.preservedRatePlan, room_number: row.dataset.preservedRoomNumber })
        }
      })
    }
    this.updateNights()
    this.toggleBackdate()
    this.updateRemoveButtons()
  }

  disconnect() {
    window.removeEventListener("booking:quote-changed", this.onQuoteChanged)
    this.overrideTimeouts.forEach((timeout) => clearTimeout(timeout))
    this.overrideTimeouts.clear()
  }

  async add() {
    const index = this.nextIndex++
    try {
      const response = await fetch(`${this.roomRowUrlValue}?index=${index}`, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error("Could not add a room row")
      this.rowsTarget.insertAdjacentHTML("beforeend", await response.text())
    } catch (error) {
      console.error("Add room row failed:", error)
      this.nextIndex--
      return
    }
    this.updateRoomRequirements()
    this.updateRemoveButtons()
  }

  remove(event) {
    if (this.rowTargets.length === 1) return
    event.currentTarget.closest("[data-booking-room-rows-target~='row']").remove()
    this.updateRemoveButtons()
    this.updateTotals()
  }

  stayChanged() {
    this.updateNights()
    this.rowTargets.forEach((row) => {
      if (!this.readValue(this.roleEl(row, "room-type"))) return

      const rateEl = this.roleEl(row, "rate-plan")
      const roomEl = this.roleEl(row, "room-number")
      this.loadRow(row, {
        rate_plan_id: this.readValue(rateEl) || row.dataset.pendingRatePlanId,
        rate_plan_label: this.selectedLabel(rateEl) || row.dataset.pendingRatePlanLabel,
        room_number: this.readValue(roomEl) || row.dataset.pendingRoomNumber,
        room_label: this.selectedLabel(roomEl) || row.dataset.pendingRoomLabel,
        notify_unavailable: true
      })
    })
  }

  // Adapter for the single range DateTimePicker: split its "startISO/endISO"
  // value into the hidden check_in / check_out fields the backend and the rest
  // of this controller already consume, then re-run the stay-dependent loads.
  rangeChanged(event) {
    if (!event.target.matches('[data-panels-ui--date-time-picker-target="input"]')) return

    const [start = "", end = ""] = (event.target.value || "").split("/")
    if (this.hasCheckInTarget) this.checkInTarget.value = start
    if (this.hasCheckOutTarget) this.checkOutTarget.value = end
    this.stayChanged()
  }

  roomTypeChanged(event) {
    const row = event.target.closest("[data-booking-room-rows-target~='row']")
    // A different category is a different quote entirely, so any hand-set
    // total from the old one no longer means anything.
    this.clearOverride(row)
    this.resetRowTotals(row)
    this.loadRow(row)
  }

  async loadRow(row, preserved = {}) {
    const requestId = String((Number(row.dataset.loadRequestId) || 0) + 1)
    row.dataset.loadRequestId = requestId
    const roomTypeId = this.readValue(this.roleEl(row, "room-type"))
    const rateEl = this.roleEl(row, "rate-plan")
    const roomEl = this.roleEl(row, "room-number")
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) {
      this.resetRowTotals(row)
      return
    }
    if (preserved.notify_unavailable) this.rememberPendingSelections(row, preserved)
    this.resetRowTotals(row)
    this.setChoices(rateEl, [{ label: "Loading rates…", value: "" }])
    this.setChoices(roomEl, [{ label: "Checking rooms…", value: "" }])

    const params = new URLSearchParams({ room_type_id: roomTypeId, check_in: this.checkInTarget.value, check_out: this.checkOutTarget.value })
    // Rate options are priced for the party staying — on a per-guest property
    // an option quoted for the wrong headcount would not match what the
    // booking is then charged.
    this.appendOccupancy(params, row)
    try {
      const [availabilityResponse, ratesResponse] = await Promise.all([
        fetch(`${this.availabilityUrlValue}?${params}`), fetch(`${this.rateOptionsUrlValue}?${params}`)
      ])
      if (!availabilityResponse.ok || !ratesResponse.ok) throw new Error("Room availability could not be loaded")
      const availability = await availabilityResponse.json()
      const rates = await ratesResponse.json()
      if (row.dataset.loadRequestId !== requestId) return

      const selectedElsewhere = this.rowTargets
        .filter((candidate) => candidate !== row)
        .map((candidate) => this.readValue(this.roleEl(candidate, "room-number")))

      const roomChoices = [{ label: this.roomPlaceholderLabel(), value: "" }].concat(
        (availability.room_options || availability.available_rooms || []).map((room) => {
          const number = String(typeof room === "string" ? room : room.room_number)
          return {
            label: typeof room === "string" ? room : (room.label || number),
            value: number,
            disabled: selectedElsewhere.includes(number) || (typeof room !== "string" && room.selectable === false)
          }
        })
      )
      const preservedRoomNumber = String(preserved.room_number || "")
      const roomStillAvailable = roomChoices.some((choice) => choice.value === preservedRoomNumber && !choice.disabled)
      this.setChoices(roomEl, roomChoices, roomStillAvailable ? preservedRoomNumber : "")

      const rateTotals = {}
      const rateChoices = [{ label: "Select rate", value: "" }].concat(
        (rates.rate_options || []).map((rate) => {
          const total = Number(rate.total_amount || 0)
          const value = String(rate.id || "")
          rateTotals[value] = total
          return { label: `${rate.name} · ${rate.currency || "MYR"} ${total.toFixed(2)}`, value: value }
        })
      )
      row.dataset.rateTotals = JSON.stringify(rateTotals)
      const preservedRatePlanId = String(preserved.rate_plan_id || "")
      const rateStillAvailable = rateChoices.some((choice) => choice.value === preservedRatePlanId)
      this.setChoices(rateEl, rateChoices, rateStillAvailable ? preservedRatePlanId : "")

      if (preserved.notify_unavailable) {
        this.notifyUnavailableSelections({
          roomUnavailable: Boolean(preservedRoomNumber) && !roomStillAvailable,
          roomLabel: preserved.room_label || preservedRoomNumber,
          rateUnavailable: Boolean(preservedRatePlanId) && !rateStillAvailable,
          rateLabel: preserved.rate_plan_label || "Selected rate plan"
        })
        this.forgetPendingSelections(row)
      }
      this.recalcRow(row)
    } catch (error) {
      if (row.dataset.loadRequestId !== requestId) return
      this.forgetPendingSelections(row)
      this.setChoices(rateEl, [{ label: "Rates unavailable", value: "" }])
      this.setChoices(roomEl, [{ label: error.message, value: "" }])
    }
  }

  // Bound to the rate-plan select only — picking a different rate is a new
  // quote, so any hand-set total is dropped rather than silently kept against
  // a price it no longer describes.
  rateChanged(event) {
    const row = event.target.closest("[data-booking-room-rows-target~='row']")
    this.clearOverride(row)
    this.recalcRow(row)
  }

  // Bound to the adults/children fields. Occupancy can change what a rate plan
  // quotes, but it does not invalidate a total the operator chose by hand —
  // recalcRow re-solves against the same target rather than dropping it.
  occupancyChanged(event) {
    this.recalcRow(event.target.closest("[data-booking-room-rows-target~='row']"))
  }

  // Typing a final total (tax included) re-solves the room net on the server:
  // BuildFinancialSnapshot's tax rules are the only place that knows how to
  // invert them correctly, so this never duplicates that math client-side.
  totalOverrideChanged(event) {
    const row = event.target.closest("[data-booking-room-rows-target~='row']")
    if (!row) return

    clearTimeout(this.overrideTimeouts.get(row))
    this.overrideTimeouts.set(row, setTimeout(() => {
      this.overrideTimeouts.delete(row)
      const raw = String(event.target.value || "").trim()
      if (raw === "") {
        this.clearOverride(row)
        this.recalcRow(row)
        return
      }
      const amount = Number(raw)
      if (!Number.isFinite(amount) || amount < 0) return

      row.dataset.targetTotal = amount
      this.solveOverride(row)
    }, 400))
  }

  hasOverride(row) {
    return Boolean(row?.dataset.targetTotal)
  }

  clearOverride(row) {
    if (!row) return
    delete row.dataset.targetTotal
    this.setManualOverrideField(row, "")
    this.breakdownEl(row, "manual-note")?.classList.add("hidden")
  }

  setManualOverrideField(row, value) {
    const field = this.roleEl(row, "manual-rate-override")
    if (field) field.value = value ?? ""
  }

  // Everything the room row cell can set the total to funnels back through
  // here: the rate-plan's own quote when there is no override, or a re-solve
  // against the standing target when there is one (occupancy, dates, or guest
  // country changing without the operator having touched the total itself).
  recalcRow(row) {
    if (!row) return
    if (this.hasOverride(row)) {
      this.solveOverride(row)
      return
    }

    const value = this.readValue(this.roleEl(row, "rate-plan"))
    const totals = row.dataset.rateTotals ? JSON.parse(row.dataset.rateTotals) : {}
    const fallbackTotal = Number(totals[value] || 0)
    row.dataset.roomTotal = fallbackTotal.toFixed(2)
    row.dataset.taxTotal = "0.00"
    row.dataset.tourismTaxTotal = "0.00"
    row.dataset.grandTotal = fallbackTotal.toFixed(2)
    this.setRateDisplay(row, fallbackTotal)
    this.updateTotals()
    this.loadRowPrice(row)
  }

  // Re-solves a row against its standing target total (guest country and tax
  // eligibility can move without the operator wanting the final price to).
  async solveOverride(row) {
    if (!this.hasPriceUrlValue) return

    const roomTypeId = this.readValue(this.roleEl(row, "room-type"))
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) return

    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: this.checkInTarget.value,
      check_out: this.checkOutTarget.value,
      target_total: row.dataset.targetTotal
    })
    this.appendOccupancy(params, row)
    const ratePlanId = this.readValue(this.roleEl(row, "rate-plan"))
    if (ratePlanId) params.set("rate_plan_id", ratePlanId)
    const guestCountry = this.hasGuestCountryTarget ? this.readValue(this.guestCountryTarget) : ""
    if (guestCountry) params.set("guest_country", guestCountry)

    const requestKey = params.toString()
    row.dataset.priceRequestKey = requestKey
    this.setPriceBreakdownStatus(row, "Calculating…")

    try {
      const response = await fetch(`${this.priceUrlValue}?${params}`)
      if (!response.ok) throw new Error("Total could not be priced")

      const data = await response.json()
      if (row.dataset.priceRequestKey !== requestKey) return

      const roomTotal = Number(data.room_total || 0)
      const taxTotal = Number(data.tax_total || 0)
      const tourismTaxTotal = Number(data.tourism_tax_total || 0)
      const grandTotal = Number(data.total_amount || roomTotal + taxTotal)

      row.dataset.roomTotal = roomTotal.toFixed(2)
      row.dataset.taxTotal = taxTotal.toFixed(2)
      row.dataset.tourismTaxTotal = tourismTaxTotal.toFixed(2)
      row.dataset.grandTotal = grandTotal.toFixed(2)
      this.setRateDisplay(row, grandTotal)
      this.setManualOverrideField(row, data.manual_rate_override)
      this.populatePriceBreakdown(row, data)
      this.updateTotals()
    } catch (error) {
      if (row.dataset.priceRequestKey !== requestKey) return
      console.error("Manual total calculation failed:", error)
      this.setPriceBreakdownStatus(row, "Could not price this total.")
    }
  }

  guestCountryChanged() {
    this.rowTargets.forEach((row) => {
      this.hasOverride(row) ? this.solveOverride(row) : this.loadRowPrice(row)
    })
  }

  resetRowTotals(row) {
    row.dataset.roomTotal = "0.00"
    row.dataset.taxTotal = "0.00"
    row.dataset.tourismTaxTotal = "0.00"
    row.dataset.grandTotal = "0.00"
    row.dataset.priceRequestKey = ""
    this.setRateDisplay(row, 0)
    this.resetPriceBreakdown(row)
    this.updateTotals()
  }

  // The Rate cell is a read-only span for staff without the pricing
  // permission and an editable input for staff who have it — set whichever
  // it is, and never fight an amount the operator is mid-typing into it.
  setRateDisplay(row, amount) {
    const el = this.roleEl(row, "rate")
    if (!el) return
    const text = Number(amount || 0).toFixed(2)
    if (el.tagName === "INPUT") {
      if (document.activeElement !== el) el.value = text
    } else {
      el.textContent = text
    }
  }

  rateDisplayValue(row) {
    const el = this.roleEl(row, "rate")
    if (!el) return 0
    return Number((el.tagName === "INPUT" ? el.value : el.textContent) || 0)
  }

  bookingType() {
    return this.hasBookingTypeTarget ? this.readValue(this.bookingTypeTarget) : "reservation"
  }

  // Reservations prepay; walk-in and backdated check-ins collect on arrival. That
  // split decides which collection switches apply and which payment methods are
  // eligible, so it is broadcast for payment-method-filter to pick up.
  toggleBackdate() {
    const bookingType = this.bookingType()
    if (this.hasBackdateFieldsTarget) this.backdateFieldsTarget.classList.toggle("hidden", bookingType !== "backdated_check_in")
    this.toggleBookingModeSections(bookingType)
    this.updateRoomRequirements()
  }

  toggleBookingModeSections(bookingType) {
    const onArrival = bookingType !== "reservation"
    this.setSectionActive(this.depositCollectionTargets, onArrival)
    this.updateTaxCollectionVisibility(bookingType)
    window.dispatchEvent(new CustomEvent("booking:mode-changed", {
      detail: { purpose: onArrival ? "direct" : "guest_advance" }
    }))
    this.updateCollection()
  }

  setSectionActive(sections, active) {
    sections.forEach((section) => {
      section.classList.toggle("hidden", !active)
      section.querySelectorAll("input, select, textarea, button").forEach((control) => { control.disabled = !active })

      if (active) {
        section.querySelectorAll('[data-controller~="payment-toggle"]').forEach((toggleElement) => {
          const toggleController = this.application.getControllerForElementAndIdentifier(toggleElement, "payment-toggle")
          toggleController?.toggle()
        })
      }
    })
  }

  updateTaxCollectionVisibility(bookingType = this.bookingType()) {
    this.setSectionActive(this.tourismTaxCollectionTargets, bookingType !== "reservation" && this.tourismTax > 0)
  }

  collectionChanged() {
    this.updateCollection()
  }

  onQuoteChanged(event) {
    this.surcharge = Number(event.detail?.surcharge || 0)
    this.surchargeTax = Number(event.detail?.surchargeTax || 0)
    this.updateCollection()
  }

  switchOn(target) {
    return Boolean(target) && !target.disabled && target.checked
  }

  // The billing summary is the sheet's only money display. Every line is listed
  // once; lines that are not being collected stay visible but muted and are left
  // out of the total, so the figure always matches what hits the drawer.
  updateCollection() {
    if (!this.hasCollectedTotalTarget) return

    const onArrival = this.bookingType() !== "reservation"
    const payingFolio = this.hasCollectPaymentTarget && this.switchOn(this.collectPaymentTarget)
    const collectingTourism = onArrival && this.tourismTax > 0 &&
      this.hasTourismTaxCollectedTarget && this.switchOn(this.tourismTaxCollectedTarget)
    const depositOn = onArrival && this.hasDepositEnabledTarget && this.switchOn(this.depositEnabledTarget)
    const deposit = depositOn && this.hasDepositAmountTarget ? Math.max(0, Number(this.depositAmountTarget.value || 0)) : 0

    // Surcharge is priced on the folio payment only — Deposits::Record takes none.
    const surcharge = payingFolio ? this.surcharge : 0
    const surchargeTax = payingFolio ? this.surchargeTax : 0

    this.toggleRow(this.surchargeRowTargets, surcharge > 0)
    this.toggleRow(this.surchargeTaxRowTargets, surchargeTax > 0)
    this.toggleRow(this.depositRowTargets, deposit > 0)
    this.surchargeTotalTargets.forEach((target) => { target.textContent = surcharge.toFixed(2) })
    this.surchargeTaxTotalTargets.forEach((target) => { target.textContent = surchargeTax.toFixed(2) })
    this.depositTotalTargets.forEach((target) => { target.textContent = deposit.toFixed(2) })

    const collecting = payingFolio || collectingTourism || deposit > 0
    const total = (payingFolio ? this.baseTotal + surcharge + surchargeTax : 0) +
      (collectingTourism ? this.tourismTax : 0) + deposit

    this.collectedLabelTargets.forEach((target) => { target.textContent = collecting ? "Total to collect" : "Total" })
    this.collectedTotalTargets.forEach((target) => { target.textContent = (collecting ? total : this.baseTotal).toFixed(2) })

    const folioUnpaid = collecting && !payingFolio
    this.folioGroupTargets.forEach((target) => target.classList.toggle("opacity-50", folioUnpaid))
    this.folioNoteTargets.forEach((target) => target.classList.toggle("hidden", !folioUnpaid))

    this.tourismTaxRowTargets.forEach((target) => target.classList.toggle("opacity-50", !collectingTourism))
    this.tourismTaxNoteTargets.forEach((target) => {
      target.textContent = collectingTourism ? "" : (onArrival ? "· not collected" : "· collect at check-in")
    })
  }

  toggleRow(targets, visible) {
    targets.forEach((target) => {
      target.classList.toggle("hidden", !visible)
      target.classList.toggle("flex", visible)
    })
  }

  updateRoomRequirements() {
    const roomRequired = !this.deferredRoomSelectionAllowed()
    this.rowTargets.forEach((row) => {
      const wrapper = this.roleEl(row, "room-number")
      let native = wrapper?.querySelector("select")
      if (!native) return

      const emptyOption = Array.from(native.options).find((option) => option.value === "")
      const placeholder = this.roomPlaceholderLabel()
      const deferredLabels = ["Select room", "Select room later", "Auto-assign"]
      if (emptyOption && deferredLabels.includes(emptyOption.textContent) && emptyOption.textContent !== placeholder) {
        const selectedValue = native.value
        const choices = Array.from(native.options).map((option) => ({
          label: option.value === "" ? placeholder : option.textContent,
          value: option.value,
          disabled: option.disabled
        }))
        this.setChoices(wrapper, choices, selectedValue)
        native = wrapper.querySelector("select")
      }
      native.required = roomRequired
    })
  }

  deferredRoomSelectionAllowed() {
    return !this.hasBookingTypeTarget || this.readValue(this.bookingTypeTarget) === "reservation"
  }

  // "Auto-assign" is a description of what leaving this blank does, not a
  // request staff make — the hotel's toggle decides it. Manual assignment is
  // still one click away by picking a room from the list underneath it.
  roomPlaceholderLabel() {
    if (!this.deferredRoomSelectionAllowed()) return "Select room"

    return this.autoAssignEnabledValue ? "Auto-assign" : "Select room later"
  }

  toggleCorporate(event) {
    // PanelsUI SelectMenu bubbles change from its inner native <select>, so read
    // the originating element (event.target), not the wrapper the action sits on.
    if (this.hasCorporateTarget) this.corporateTarget.classList.toggle("hidden", event.target.value !== "corporate")
  }

  // Party size for a row, if the row has the fields. Left off entirely when
  // blank so the server keeps its own default rather than reading "".
  appendOccupancy(params, row) {
    const adults = this.readValue(this.roleEl(row, "adults"))
    const children = this.readValue(this.roleEl(row, "children"))
    if (adults) params.set("adults", adults)
    if (children) params.set("children", children)
  }

  // The [data-role] wrapper for a row cell.
  roleEl(row, role) {
    return row.querySelector(`[data-role='${role}']`)
  }

  // Resolve a value from a target that may be a PanelsUI control wrapper (whose
  // real value lives on an inner native <select>/<input>) or a plain field.
  readValue(target) {
    if (!target) return ""
    const inner = target.querySelector?.("select, input, textarea")
    return inner ? inner.value : (target.value ?? "")
  }

  selectedLabel(target) {
    const select = target?.querySelector?.("select")
    return select?.selectedOptions?.[0]?.textContent?.trim() || ""
  }

  rememberPendingSelections(row, preserved) {
    row.dataset.pendingRatePlanId = preserved.rate_plan_id || ""
    row.dataset.pendingRatePlanLabel = preserved.rate_plan_label || ""
    row.dataset.pendingRoomNumber = preserved.room_number || ""
    row.dataset.pendingRoomLabel = preserved.room_label || ""
  }

  forgetPendingSelections(row) {
    delete row.dataset.pendingRatePlanId
    delete row.dataset.pendingRatePlanLabel
    delete row.dataset.pendingRoomNumber
    delete row.dataset.pendingRoomLabel
  }

  notifyUnavailableSelections({ roomUnavailable, roomLabel, rateUnavailable, rateLabel }) {
    if (!roomUnavailable && !rateUnavailable) return

    const selections = []
    if (roomUnavailable) selections.push(`Room ${roomLabel}`)
    if (rateUnavailable) selections.push(rateLabel)
    const subject = selections.length === 2 ? selections.join(" and ") : selections[0]
    const verb = selections.length === 2 ? "are" : "is"
    window.toast?.(`${subject} ${verb} no longer available for the selected dates. Please choose again.`, { type: "error" })
  }

  // Replace a SelectMenu's option set at runtime. Prefers the controller's public
  // replaceOptions API; before the control is enhanced, seeds the native <select>
  // (which SelectMenu reads verbatim on connect).
  setChoices(wrapper, choices, selectedValue = "") {
    if (!wrapper) return
    const host = wrapper.querySelector('[data-controller~="panels-ui--select-menu"]')
    const controller = host && this.application.getControllerForElementAndIdentifier(host, "panels-ui--select-menu")
    if (controller) {
      controller.replaceOptions(choices, selectedValue)
      return
    }
    const native = wrapper.querySelector("select")
    if (!native) return
    native.replaceChildren(...choices.map((choice) => {
      const option = new Option(choice.label, choice.value)
      option.disabled = Boolean(choice.disabled)
      return option
    }))
    native.value = selectedValue || ""
  }

  updateNights() {
    const start = new Date(this.checkInTarget.value)
    const finish = new Date(this.checkOutTarget.value)
    const nights = Math.max(0, Math.ceil((finish - start) / 86400000)) || 0
    this.nightsTarget.textContent = nights
  }

  updateTotals() {
    const roomTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.roomTotal || 0), 0)
    const taxTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.taxTotal || 0), 0)
    const tourismTaxTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.tourismTaxTotal || 0), 0)
    const grandTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.grandTotal || this.rateDisplayValue(row) || 0), 0)

    this.baseTotal = grandTotal
    this.tourismTax = tourismTaxTotal

    this.roomTotalTargets.forEach((target) => { target.textContent = roomTotal.toFixed(2) })
    this.taxTotalTargets.forEach((target) => { target.textContent = taxTotal.toFixed(2) })
    this.tourismTaxTotalTargets.forEach((target) => { target.textContent = tourismTaxTotal.toFixed(2) })
    this.grandTotalTargets.forEach((target) => { target.textContent = grandTotal.toFixed(2) })
    this.toggleRow(this.tourismTaxRowTargets, tourismTaxTotal > 0)
    this.updateTaxCollectionVisibility()
    this.updateCollection()
    window.dispatchEvent(new CustomEvent("booking:totals-changed", { detail: { amount: grandTotal } }))
  }

  async loadRowPrice(row) {
    if (!this.hasPriceUrlValue) return

    const roomTypeId = this.readValue(this.roleEl(row, "room-type"))
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) return

    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: this.checkInTarget.value,
      check_out: this.checkOutTarget.value
    })

    this.appendOccupancy(params, row)

    const ratePlanId = this.readValue(this.roleEl(row, "rate-plan"))
    if (ratePlanId) params.set("rate_plan_id", ratePlanId)
    const guestCountry = this.hasGuestCountryTarget ? this.readValue(this.guestCountryTarget) : ""
    if (guestCountry) params.set("guest_country", guestCountry)

    const requestKey = params.toString()
    row.dataset.priceRequestKey = requestKey
    this.setPriceBreakdownStatus(row, "Calculating…")

    try {
      const response = await fetch(`${this.priceUrlValue}?${params}`)
      if (!response.ok) throw new Error("Price could not be loaded")

      const data = await response.json()
      if (row.dataset.priceRequestKey !== requestKey) return

      const roomTotal = Number(data.room_total || 0)
      const taxTotal = Number(data.tax_total || 0)
      const tourismTaxTotal = Number(data.tourism_tax_total || 0)
      const grandTotal = Number(data.total_amount || roomTotal + taxTotal)

      row.dataset.roomTotal = roomTotal.toFixed(2)
      row.dataset.taxTotal = taxTotal.toFixed(2)
      row.dataset.tourismTaxTotal = tourismTaxTotal.toFixed(2)
      row.dataset.grandTotal = grandTotal.toFixed(2)
      this.setRateDisplay(row, grandTotal)
      this.populatePriceBreakdown(row, data)
      this.updateTotals()
    } catch (error) {
      if (row.dataset.priceRequestKey !== requestKey) return
      console.error("Row price calculation failed:", error)
      this.setPriceBreakdownStatus(row, "Rate breakdown unavailable.")
    }
  }

  resetPriceBreakdown(row) {
    const status = this.breakdownEl(row, "breakdown-status")
    const details = this.breakdownEl(row, "breakdown-details")
    if (status) {
      status.textContent = "Select a room type, dates, and rate plan."
      status.classList.remove("hidden")
    }
    details?.classList.add("hidden")
  }

  setPriceBreakdownStatus(row, message) {
    const status = this.breakdownEl(row, "breakdown-status")
    const details = this.breakdownEl(row, "breakdown-details")
    if (status) {
      status.textContent = message
      status.classList.remove("hidden")
    }
    details?.classList.add("hidden")
  }

  populatePriceBreakdown(row, data) {
    const status = this.breakdownEl(row, "breakdown-status")
    const details = this.breakdownEl(row, "breakdown-details")
    const nightly = this.breakdownEl(row, "nightly-breakdown")
    const taxes = this.breakdownEl(row, "tax-breakdown")
    if (!details || !nightly || !taxes) return

    const snapshot = data.nightly_rate_snapshot || {}
    const taxLines = data.tax_lines || []
    const firstNight = Object.values(snapshot)[0] || {}
    const currency = firstNight.currency || taxLines[0]?.currency || "MYR"

    this.breakdownEl(row, "manual-note")?.classList.toggle("hidden", !this.hasOverride(row))

    nightly.replaceChildren(this.buildBreakdownHeading("Nightly rates"))
    Object.entries(snapshot)
      .sort(([firstDate], [secondDate]) => firstDate.localeCompare(secondDate))
      .forEach(([date, rate]) => {
        nightly.appendChild(this.buildBreakdownRow(this.formatBreakdownDate(date), rate.price, currency))
      })
    nightly.appendChild(this.buildBreakdownRow("Room subtotal", data.room_total, currency, true))

    taxes.replaceChildren(this.buildBreakdownHeading("Taxes"))
    const payableTaxes = taxLines.filter((tax) => !this.isTourismTax(tax))
    if (payableTaxes.length === 0) {
      taxes.appendChild(this.buildBreakdownRow("Taxes", 0, currency))
    } else {
      payableTaxes.forEach((tax) => {
        taxes.appendChild(this.buildBreakdownRow(tax.name || "Tax", tax.amount, tax.currency || currency))
      })
    }

    const total = this.breakdownEl(row, "breakdown-total")
    if (total) total.textContent = this.formatBreakdownMoney(currency, data.total_amount)

    const tourismTax = Number(data.tourism_tax_total || 0)
    const tourismRow = this.breakdownEl(row, "tourism-tax-breakdown")
    const tourismAmount = this.breakdownEl(row, "tourism-tax-amount")
    if (tourismRow) {
      tourismRow.classList.toggle("hidden", tourismTax <= 0)
      tourismRow.classList.toggle("flex", tourismTax > 0)
    }
    if (tourismAmount) tourismAmount.textContent = this.formatBreakdownMoney(currency, tourismTax)

    status?.classList.add("hidden")
    details.classList.remove("hidden")
  }

  breakdownEl(row, role) {
    return row.querySelector(`[data-role='price-breakdown'] [data-role='${role}']`)
  }

  buildBreakdownHeading(text) {
    const heading = document.createElement("p")
    heading.className = "pb-0.5 text-xs font-semibold text-foreground"
    heading.textContent = text
    return heading
  }

  buildBreakdownRow(labelText, amount, currency, strong = false) {
    const item = document.createElement("div")
    item.className = `flex items-center justify-between gap-3 ${strong ? "font-medium text-foreground" : "text-muted-foreground"}`

    const label = document.createElement("span")
    label.className = "min-w-0 truncate"
    label.textContent = labelText

    const value = document.createElement("span")
    value.className = `shrink-0 whitespace-nowrap ${strong ? "font-semibold" : "font-medium text-foreground"}`
    value.textContent = this.formatBreakdownMoney(currency, amount)

    item.append(label, value)
    return item
  }

  formatBreakdownDate(date) {
    return new Intl.DateTimeFormat(undefined, {
      day: "2-digit",
      month: "short",
      year: "numeric",
      timeZone: "UTC"
    }).format(new Date(`${date}T00:00:00Z`))
  }

  formatBreakdownMoney(currency, amount) {
    return `${currency} ${Number(amount || 0).toFixed(2)}`
  }

  isTourismTax(tax) {
    return [tax.type, tax.primary_tax_key].some((value) => ["tourism_tax", "ttx"].includes(String(value || "")))
  }

  updateRemoveButtons() {
    this.rowTargets.forEach((row, index) => { this.roleEl(row, "remove").disabled = index === 0 })
  }
}
