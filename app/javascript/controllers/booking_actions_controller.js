import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    id: String,
    status: String,
    checkIn: String,
    checkOut: String,
    guestName: String,
    dateRange: String,
    source: String,
    paymentStatus: String,
    notes: String
  }

  openBookingSheet(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/booking_sheet`

    this.triggerOffcanvas(url, "compact-right")
  }

  openCheckIn(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const url = event?.currentTarget?.dataset?.bookingActionsUrlValue ||
      `/hotel/${window.location.pathname.split('/')[2]}/reservation-board/bookings/${this.idValue}/check_in`

    this.triggerOffcanvas(url, "right")
  }

  openCheckOut(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const url = event?.currentTarget?.dataset?.bookingActionsUrlValue ||
      `/hotel/${window.location.pathname.split('/')[2]}/reservation-board/bookings/${this.idValue}/check_out`

    this.triggerOffcanvas(url, "right")
  }

  openNotes(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/notes`

    this.triggerOffcanvas(url, "right")
  }

  openEditStay(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/edit_stay`

    this.triggerOffcanvas(url, "right")
  }

  openLateCheckout(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/late_checkout`

    this.triggerOffcanvas(url, "right")
  }

  triggerOffcanvas(url, variant = "right") {
    // Create a hidden anchor and click it to trigger Turbo + offcanvas
    const link = document.createElement("a")
    link.href = url
    link.setAttribute("data-turbo-frame", "offcanvas_drawer")
    link.setAttribute("data-offcanvas-variant", variant)
    link.style.display = "none"
    document.body.appendChild(link)
    link.click()
    link.remove()
  }
}
