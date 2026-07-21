import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "checkIn", "checkOut", "nights", "bookingType", "backdateFields", "corporate", "guestCountry", "roomTotal", "taxTotal", "tourismTaxRow", "tourismTaxTotal", "grandTotal"]
  static values = { availabilityUrl: String, rateOptionsUrl: String, priceUrl: String, roomRowUrl: String }

  connect() {
    this.nextIndex = this.rowTargets.length
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
      if (this.readValue(this.roleEl(row, "room-type"))) this.loadRow(row)
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
    this.resetRowTotals(row)
    this.loadRow(row)
  }

  async loadRow(row, preserved = {}) {
    const roomTypeId = this.readValue(this.roleEl(row, "room-type"))
    const rateEl = this.roleEl(row, "rate-plan")
    const roomEl = this.roleEl(row, "room-number")
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) {
      this.resetRowTotals(row)
      return
    }
    this.resetRowTotals(row)
    this.setChoices(rateEl, [{ label: "Loading rates…", value: "" }])
    this.setChoices(roomEl, [{ label: "Checking rooms…", value: "" }])

    const params = new URLSearchParams({ room_type_id: roomTypeId, check_in: this.checkInTarget.value, check_out: this.checkOutTarget.value })
    try {
      const [availabilityResponse, ratesResponse] = await Promise.all([
        fetch(`${this.availabilityUrlValue}?${params}`), fetch(`${this.rateOptionsUrlValue}?${params}`)
      ])
      if (!availabilityResponse.ok || !ratesResponse.ok) throw new Error("Room availability could not be loaded")
      const availability = await availabilityResponse.json()
      const rates = await ratesResponse.json()
      const selectedElsewhere = this.rowTargets
        .filter((candidate) => candidate !== row)
        .map((candidate) => this.readValue(this.roleEl(candidate, "room-number")))

      const roomChoices = [{ label: "Select room", value: "" }].concat(
        (availability.room_options || availability.available_rooms || []).map((room) => {
          const number = String(typeof room === "string" ? room : room.room_number)
          return {
            label: typeof room === "string" ? room : (room.label || number),
            value: number,
            disabled: selectedElsewhere.includes(number) || (typeof room !== "string" && room.selectable === false)
          }
        })
      )
      this.setChoices(roomEl, roomChoices, preserved.room_number || "")

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
      this.setChoices(rateEl, rateChoices, preserved.rate_plan_id || "")
      this.recalcRow(row)
    } catch (error) {
      this.setChoices(rateEl, [{ label: "Rates unavailable", value: "" }])
      this.setChoices(roomEl, [{ label: error.message, value: "" }])
    }
  }

  rateChanged(event) {
    this.recalcRow(event.target.closest("[data-booking-room-rows-target~='row']"))
  }

  recalcRow(row) {
    if (!row) return
    const value = this.readValue(this.roleEl(row, "rate-plan"))
    const totals = row.dataset.rateTotals ? JSON.parse(row.dataset.rateTotals) : {}
    const fallbackTotal = Number(totals[value] || 0)
    row.dataset.roomTotal = fallbackTotal.toFixed(2)
    row.dataset.taxTotal = "0.00"
    row.dataset.tourismTaxTotal = "0.00"
    row.dataset.grandTotal = fallbackTotal.toFixed(2)
    this.roleEl(row, "rate").textContent = fallbackTotal.toFixed(2)
    this.updateTotals()
    this.loadRowPrice(row)
  }

  guestCountryChanged() {
    this.rowTargets.forEach((row) => this.loadRowPrice(row))
  }

  resetRowTotals(row) {
    row.dataset.roomTotal = "0.00"
    row.dataset.taxTotal = "0.00"
    row.dataset.tourismTaxTotal = "0.00"
    row.dataset.grandTotal = "0.00"
    row.dataset.priceRequestKey = ""
    this.roleEl(row, "rate").textContent = "0.00"
    this.updateTotals()
  }

  toggleBackdate() {
    if (this.hasBackdateFieldsTarget) this.backdateFieldsTarget.classList.toggle("hidden", this.readValue(this.bookingTypeTarget) !== "backdated_check_in")
    this.updateRoomRequirements()
  }

  updateRoomRequirements() {
    const roomRequired = this.hasBookingTypeTarget && this.readValue(this.bookingTypeTarget) !== "reservation"
    this.rowTargets.forEach((row) => {
      const native = this.roleEl(row, "room-number")?.querySelector("select")
      if (native) native.required = roomRequired
    })
  }

  toggleCorporate(event) {
    // PanelsUI SelectMenu bubbles change from its inner native <select>, so read
    // the originating element (event.target), not the wrapper the action sits on.
    if (this.hasCorporateTarget) this.corporateTarget.classList.toggle("hidden", event.target.value !== "corporate")
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

  moreOptions(event) {
    event.preventDefault()
    const url = new URL(event.currentTarget.href, window.location.origin)
    const data = new FormData(this.element.querySelector("form"))
    data.forEach((value, key) => url.searchParams.append(key, value))

    const openFullForm = () => {
      const link = document.createElement("a")
      link.href = url.toString()
      link.dataset.turboFrame = "offcanvas_drawer"
      link.dataset.offcanvasVariant = "fullscreen-bottom"
      link.hidden = true
      document.body.appendChild(link)
      link.click()
      link.remove()
    }

    const container = document.getElementById("offcanvas_drawer_container")
    const offcanvas = container && window.Stimulus?.getControllerForElementAndIdentifier(container, "offcanvas")
    if (!offcanvas) return openFullForm()

    offcanvas.close()
    setTimeout(openFullForm, 325)
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
    const grandTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.grandTotal || this.roleEl(row, "rate").textContent || 0), 0)

    this.roomTotalTargets.forEach((target) => { target.textContent = roomTotal.toFixed(2) })
    this.taxTotalTargets.forEach((target) => { target.textContent = taxTotal.toFixed(2) })
    this.tourismTaxTotalTargets.forEach((target) => { target.textContent = tourismTaxTotal.toFixed(2) })
    this.grandTotalTargets.forEach((target) => { target.textContent = grandTotal.toFixed(2) })
    this.tourismTaxRowTargets.forEach((target) => target.classList.toggle("hidden", tourismTaxTotal <= 0))
    this.tourismTaxRowTargets.forEach((target) => target.classList.toggle("flex", tourismTaxTotal > 0))
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

    const ratePlanId = this.readValue(this.roleEl(row, "rate-plan"))
    if (ratePlanId) params.set("rate_plan_id", ratePlanId)
    const guestCountry = this.hasGuestCountryTarget ? this.readValue(this.guestCountryTarget) : ""
    if (guestCountry) params.set("guest_country", guestCountry)

    const requestKey = params.toString()
    row.dataset.priceRequestKey = requestKey

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
      this.roleEl(row, "rate").textContent = grandTotal.toFixed(2)
      this.updateTotals()
    } catch (error) {
      console.error("Row price calculation failed:", error)
    }
  }

  updateRemoveButtons() {
    this.rowTargets.forEach((row, index) => { this.roleEl(row, "remove").disabled = index === 0 })
  }
}
