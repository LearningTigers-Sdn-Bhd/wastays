import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "template", "checkIn", "checkOut", "nights", "bookingType", "backdateFields", "corporate", "guestCountry", "roomTotal", "taxTotal", "tourismTaxRow", "tourismTaxTotal", "grandTotal"]
  static values = { availabilityUrl: String, rateOptionsUrl: String, priceUrl: String, initialRows: Array }

  connect() {
    this.nextIndex = this.rowTargets.length
    if (this.rowTargets.length === 0) {
      const rows = this.hasInitialRowsValue && this.initialRowsValue.length > 0 ? this.initialRowsValue : [{}]
      rows.forEach((values) => this.addRow(values))
    }
    this.updateNights()
    this.toggleBackdate()
  }

  add() {
    this.addRow({})
  }

  addRow(values) {
    const index = this.nextIndex++
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("INDEX", index))
    const row = this.rowTargets[this.rowTargets.length - 1]
    row.querySelector("[data-role='room-type']").value = values.room_type_id || ""
    row.querySelector("input[name$='[adults]']").value = values.adults || 1
    row.querySelector("input[name$='[children]']").value = values.children || 0
    if (values.room_type_id) this.loadRow(row, values)
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
      const roomType = row.querySelector("[data-role='room-type']")
      if (roomType.value) this.loadRow(row)
    })
  }

  roomTypeChanged(event) {
    const row = event.currentTarget.closest("[data-booking-room-rows-target~='row']")
    this.resetRowTotals(row)
    this.loadRow(row)
  }

  async loadRow(row, preserved = {}) {
    const roomTypeId = row.querySelector("[data-role='room-type']").value
    const roomSelect = row.querySelector("[data-role='room-number']")
    const rateSelect = row.querySelector("[data-role='rate-plan']")
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) {
      this.resetRowTotals(row)
      return
    }
    this.resetRowTotals(row)

    roomSelect.disabled = true
    roomSelect.innerHTML = '<option value="">Checking rooms…</option>'
    rateSelect.disabled = true
    rateSelect.innerHTML = '<option value="">Loading rates…</option>'

    const params = new URLSearchParams({ room_type_id: roomTypeId, check_in: this.checkInTarget.value, check_out: this.checkOutTarget.value })
    try {
      const [availabilityResponse, ratesResponse] = await Promise.all([
        fetch(`${this.availabilityUrlValue}?${params}`), fetch(`${this.rateOptionsUrlValue}?${params}`)
      ])
      if (!availabilityResponse.ok || !ratesResponse.ok) throw new Error("Room availability could not be loaded")
      const availability = await availabilityResponse.json()
      const rates = await ratesResponse.json()
      const selectedElsewhere = this.rowTargets.filter((candidate) => candidate !== row).map((candidate) => candidate.querySelector("[data-role='room-number']").value)

      roomSelect.innerHTML = '<option value="">Select room</option>'
      ;(availability.room_options || availability.available_rooms || []).forEach((room) => {
        const number = typeof room === "string" ? room : room.room_number
        const option = new Option(typeof room === "string" ? room : (room.label || number), number)
        option.disabled = selectedElsewhere.includes(String(number)) || (typeof room !== "string" && room.selectable === false)
        roomSelect.add(option)
      })
      roomSelect.disabled = false
      roomSelect.value = preserved.room_number || ""

      rateSelect.innerHTML = '<option value="">Select rate</option>'
      ;(rates.rate_options || []).forEach((rate) => {
        const total = Number(rate.total_amount || 0)
        const option = new Option(`${rate.name} · ${rate.currency || "MYR"} ${total.toFixed(2)}`, rate.id || "")
        option.dataset.total = total
        rateSelect.add(option)
      })
      rateSelect.disabled = false
      rateSelect.value = preserved.rate_plan_id || ""
      this.rateChanged({ currentTarget: rateSelect })
    } catch (error) {
      roomSelect.innerHTML = `<option value="">${error.message}</option>`
      rateSelect.innerHTML = '<option value="">Rates unavailable</option>'
    }
  }

  rateChanged(event) {
    const row = event.currentTarget.closest("[data-booking-room-rows-target~='row']")
    const selected = event.currentTarget.selectedOptions[0]
    const fallbackTotal = Number(selected?.dataset.total || 0)
    row.dataset.roomTotal = fallbackTotal.toFixed(2)
    row.dataset.taxTotal = "0.00"
    row.dataset.tourismTaxTotal = "0.00"
    row.dataset.grandTotal = fallbackTotal.toFixed(2)
    row.querySelector("[data-role='rate']").textContent = fallbackTotal.toFixed(2)
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
    row.querySelector("[data-role='rate']").textContent = "0.00"
    this.updateTotals()
  }

  toggleBackdate() {
    if (this.hasBackdateFieldsTarget) this.backdateFieldsTarget.classList.toggle("hidden", this.bookingTypeTarget.value !== "backdated_check_in")
    this.updateRoomRequirements()
  }

  updateRoomRequirements() {
    const roomRequired = this.hasBookingTypeTarget && this.bookingTypeTarget.value !== "reservation"
    this.rowTargets.forEach((row) => { row.querySelector("[data-role='room-number']").required = roomRequired })
  }

  toggleCorporate(event) {
    if (this.hasCorporateTarget) this.corporateTarget.classList.toggle("hidden", event.currentTarget.value !== "corporate")
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
    const grandTotal = this.rowTargets.reduce((sum, row) => sum + Number(row.dataset.grandTotal || row.querySelector("[data-role='rate']").textContent || 0), 0)

    this.roomTotalTargets.forEach((target) => { target.textContent = roomTotal.toFixed(2) })
    this.taxTotalTargets.forEach((target) => { target.textContent = taxTotal.toFixed(2) })
    this.tourismTaxTotalTargets.forEach((target) => { target.textContent = tourismTaxTotal.toFixed(2) })
    this.grandTotalTargets.forEach((target) => { target.textContent = grandTotal.toFixed(2) })
    this.tourismTaxRowTargets.forEach((target) => target.classList.toggle("hidden", tourismTaxTotal <= 0))
    this.tourismTaxRowTargets.forEach((target) => target.classList.toggle("flex", tourismTaxTotal > 0))
  }

  async loadRowPrice(row) {
    if (!this.hasPriceUrlValue) return

    const roomTypeId = row.querySelector("[data-role='room-type']")?.value
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) return

    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: this.checkInTarget.value,
      check_out: this.checkOutTarget.value
    })

    const ratePlanId = row.querySelector("[data-role='rate-plan']")?.value
    if (ratePlanId) params.set("rate_plan_id", ratePlanId)
    if (this.hasGuestCountryTarget && this.guestCountryTarget.value) params.set("guest_country", this.guestCountryTarget.value)

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
      row.querySelector("[data-role='rate']").textContent = grandTotal.toFixed(2)
      this.updateTotals()
    } catch (error) {
      console.error("Row price calculation failed:", error)
    }
  }

  updateRemoveButtons() {
    this.rowTargets.forEach((row, index) => { row.querySelector("[data-role='remove']").disabled = index === 0 })
  }
}
