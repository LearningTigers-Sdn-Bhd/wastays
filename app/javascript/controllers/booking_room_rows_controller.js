import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "template", "checkIn", "checkOut", "nights", "bookingType", "backdateFields", "corporate", "roomTotal", "grandTotal"]
  static values = { availabilityUrl: String, rateOptionsUrl: String, initialRows: Array }

  connect() {
    this.nextIndex = this.rowTargets.length
    if (this.rowTargets.length === 0) {
      const rows = this.hasInitialRowsValue && this.initialRowsValue.length > 0 ? this.initialRowsValue : [{}]
      rows.forEach((values) => this.addRow(values))
    }
    this.updateNights()
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
    this.loadRow(event.currentTarget.closest("[data-booking-room-rows-target~='row']"))
  }

  async loadRow(row, preserved = {}) {
    const roomTypeId = row.querySelector("[data-role='room-type']").value
    const roomSelect = row.querySelector("[data-role='room-number']")
    const rateSelect = row.querySelector("[data-role='rate-plan']")
    if (!roomTypeId || !this.checkInTarget.value || !this.checkOutTarget.value) return

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
    row.querySelector("[data-role='rate']").textContent = Number(selected?.dataset.total || 0).toFixed(2)
    this.updateTotals()
  }

  toggleBackdate() {
    if (this.hasBackdateFieldsTarget) this.backdateFieldsTarget.classList.toggle("hidden", this.bookingTypeTarget.value !== "backdated_check_in")
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
    const total = this.rowTargets.reduce((sum, row) => sum + Number(row.querySelector("[data-role='rate']").textContent || 0), 0)
    if (this.hasRoomTotalTarget) this.roomTotalTarget.textContent = total.toFixed(2)
    if (this.hasGrandTotalTarget) this.grandTotalTarget.textContent = total.toFixed(2)
  }

  updateRemoveButtons() {
    this.rowTargets.forEach((row, index) => { row.querySelector("[data-role='remove']").disabled = index === 0 })
  }
}
