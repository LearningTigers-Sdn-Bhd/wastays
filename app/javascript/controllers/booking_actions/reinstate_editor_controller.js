import { Controller } from "@hotwired/stimulus"

// Per-booking room re-selection for the Reinstate Sheet. When the room
// category changes, it refreshes the room-number and rate menus from
// availability so a no-show stay is checked back in against a room that is
// actually free for its dates. Dates are fixed (the scheduled stay), so the
// availability window is always valid.
//
// One instance is mounted per booking panel (single booking, or each child in
// a group), so its targets only ever address that booking's fields.
export default class extends Controller {
  static targets = ["roomType", "ratePlan", "roomNumber"]
  static values = {
    availabilityUrl: String,
    rateOptionsUrl: String,
    bookingId: String,
    checkIn: String,
    checkOut: String
  }

  connect() {
    this.sequence = 0
  }

  async categoryChanged() {
    const roomTypeId = this.roomTypeTarget.value
    if (!roomTypeId) return

    const sequence = ++this.sequence
    const [rooms, rates] = await Promise.all([
      this.fetchRooms(roomTypeId),
      this.fetchRates(roomTypeId)
    ])
    if (sequence !== this.sequence) return

    if (this.hasRoomNumberTarget) this.replaceOptions(this.roomNumberTarget, rooms)
    if (this.hasRatePlanTarget) this.replaceOptions(this.ratePlanTarget, rates, { blank: "Select a rate" })
  }

  async fetchRooms(roomTypeId) {
    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: this.checkInValue,
      check_out: this.checkOutValue,
      exclude_booking_id: this.bookingIdValue
    })
    const response = await fetch(`${this.availabilityUrlValue}?${params}`)
    if (!response.ok) return []
    const payload = await response.json()
    return Array.from(payload.room_options || []).map((room) => ({
      label: room.label || room.room_number,
      value: String(room.room_number),
      disabled: !room.selectable
    }))
  }

  async fetchRates(roomTypeId) {
    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: this.checkInValue,
      check_out: this.checkOutValue
    })
    const response = await fetch(`${this.rateOptionsUrlValue}?${params}`)
    if (!response.ok) return []
    const payload = await response.json()
    // Only real rate plans (numeric id) are valid reinstate rate_plan_ids;
    // walk-in/corporate tier tokens and the nil base rate are excluded.
    return Array.from(payload.rate_options || [])
      .filter((option) => Number.isInteger(option.id))
      .map((option) => ({ label: option.name, value: String(option.id) }))
  }

  // Rebuild a native <select> from freshly fetched options, preserving the
  // prior selection when it is still selectable.
  replaceOptions(select, options, { blank } = {}) {
    const previous = select.value
    const elements = []

    if (blank) {
      elements.push(this.buildOption({ label: blank, value: "" }))
    }

    if (!options.length && !blank) {
      elements.push(this.buildOption({ label: "No rooms available", value: "", disabled: true }))
      select.replaceChildren(...elements)
      return
    }

    options.forEach((option) => elements.push(this.buildOption(option)))
    select.replaceChildren(...elements)

    const stillSelectable = options.some((option) => option.value === previous && !option.disabled)
    select.value = stillSelectable ? previous : (blank ? "" : (options.find((option) => !option.disabled)?.value || ""))
  }

  buildOption({ label, value, disabled }) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    if (disabled) option.disabled = true
    return option
  }
}
