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
    if (event?.target?.closest('[data-booking-timeline-target="dragHandle"], [data-booking-timeline-target="resizeHandle"]')) return
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/booking-transactions/show-booking/${this.idValue}?source=booking_timeline_board`

    this.triggerOffcanvas(url, "compact-right")
  }

  openCheckIn(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const url = event?.currentTarget?.dataset?.bookingActionsUrlValue ||
      `/hotel/${window.location.pathname.split('/')[2]}/booking-transactions/check-in-reservation/${this.idValue}?source=booking_timeline_board`

    this.triggerOffcanvas(url, "right")
  }

  openCheckOut(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const url = event?.currentTarget?.dataset?.bookingActionsUrlValue ||
      `/hotel/${window.location.pathname.split('/')[2]}/booking-transactions/check-out/${this.idValue}?source=booking_timeline_board`

    this.triggerOffcanvas(url, "right")
  }

  openNotes(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/bookings/${this.idValue}`

    this.triggerOffcanvas(url, "right")
  }

  openEditStay(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/booking-transactions/amend-stay/${this.idValue}?source=booking_timeline_board`

    this.triggerOffcanvas(url, "right")
  }

  openLateCheckout(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/booking-transactions/late-checkout/${this.idValue}?source=booking_timeline_board`

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
