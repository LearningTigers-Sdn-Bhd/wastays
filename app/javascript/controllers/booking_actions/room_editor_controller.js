import { Controller } from "@hotwired/stimulus"

// Refreshes the room-number menu on the Room Sheet when the room category
// changes. Dates are fixed on this sheet (submitted as hidden fields), so the
// availability query always has a valid window.
export default class extends Controller {
  static values = { availabilityUrl: String, bookingId: String }

  connect() {
    this.requestSequence = 0
  }

  changed(event) {
    if (event.target.id !== "booking_room_type_id") return
    this.refresh()
  }

  async refresh() {
    const roomTypeId = this.field("booking_room_type_id")
    const checkIn = this.field("booking_check_in")
    const checkOut = this.field("booking_check_out")
    if (!roomTypeId || !checkIn || !checkOut) return

    const sequence = ++this.requestSequence
    const params = new URLSearchParams({
      room_type_id: roomTypeId,
      check_in: checkIn,
      check_out: checkOut,
      exclude_booking_id: this.bookingIdValue
    })
    const response = await fetch(`${this.availabilityUrlValue}?${params}`)
    if (!response.ok) return
    const payload = await response.json()
    if (sequence !== this.requestSequence) return

    this.replaceMenu("booking_room_number", this.roomChoices(payload), this.field("booking_room_number"))
  }

  roomChoices(payload) {
    const choices = Array.from(payload.room_options || []).map((room) => ({
      label: room.label || room.room_number,
      value: room.room_number,
      disabled: !room.selectable
    }))
    return choices.length ? choices : [{ label: "No rooms available", value: "", disabled: true }]
  }

  replaceMenu(id, choices, selectedValue) {
    const native = this.element.querySelector(`#${CSS.escape(id)}`)
    const root = native?.closest("[data-controller~='panels-ui--select-menu']")
    const controller = root && this.application.getControllerForElementAndIdentifier(root, "panels-ui--select-menu")
    controller?.replaceOptions(choices, selectedValue || "")
  }

  field(id) {
    return this.element.querySelector(`#${CSS.escape(id)}`)?.value || ""
  }
}
