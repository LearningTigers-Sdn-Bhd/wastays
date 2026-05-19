import { Controller } from "@hotwired/stimulus"
import { computePosition, flip, shift, offset } from "@floating-ui/dom"

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
  static targets = ["checkInBtn", "checkOutBtn", "detailsBtn", "openNotesBtn", "guestNameDisplay", "dateRangeDisplay", "statusDisplay", "sourceBadge", "paymentBadge"]

  showMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    this.removeExistingMenu()

    const template = document.getElementById("booking-actions-menu-template")
    const menu = template.content.cloneNode(true).firstElementChild
    menu.id = "active-booking-menu"
    
    // Create overlay to prevent click-through
    const overlay = document.createElement("div")
    overlay.id = "active-booking-overlay"
    overlay.className = "fixed inset-0 z-[90]"
    overlay.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.removeExistingMenu()
    })
    document.body.appendChild(overlay)

    // Populate dynamic content
    menu.querySelector('[data-booking-actions-target="guestNameDisplay"]').textContent = this.guestNameValue
    menu.querySelector('[data-booking-actions-target="dateRangeDisplay"]').textContent = this.dateRangeValue
    menu.querySelector('[data-booking-actions-target="statusDisplay"]').textContent = this.statusValue.replace(/_/g, " ")

    // Badges
    const sourceBadge = menu.querySelector('[data-booking-actions-target="sourceBadge"]')
    sourceBadge.textContent = this.sourceValue || "Direct"
    sourceBadge.className += this.sourceValue === "internal" ? " bg-slate-200/60 text-slate-600" : " bg-blue-100 text-blue-700"

    const paymentBadge = menu.querySelector('[data-booking-actions-target="paymentBadge"]')
    paymentBadge.textContent = this.paymentStatusValue.replace(/_/g, " ").toUpperCase()
    paymentBadge.className += this.paymentStatusValue === "captured" ? " bg-emerald-100 text-emerald-700" : " bg-amber-100 text-amber-700"

    // Notes Button logic
    if (this.notesValue && this.notesValue !== "undefined" && this.notesValue !== "" && this.notesValue !== "[]") {
      const openNotesBtn = menu.querySelector('[data-booking-actions-target="openNotesBtn"]')
      openNotesBtn.classList.remove("hidden")
      openNotesBtn.addEventListener("click", (e) => this.openNotes(e))
    }

    const hotelId = window.location.pathname.split('/')[2]
    const detailsUrl = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}`
    const checkInUrl = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/check_in`
    const checkOutUrl = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/check_out`
    
    // Configure buttons based on state
    const isConfirmed = this.statusValue === "confirmed"
    const isCheckedIn = this.statusValue === "checked_in"
    
    const checkInBtn = menu.querySelector('[data-booking-actions-target="checkInBtn"]')
    if (isConfirmed || isCheckedIn) {
      checkInBtn.classList.remove("hidden")
      if (isCheckedIn) {
        checkInBtn.innerHTML = `
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="size-4"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
          Edit Check-In
        `
      }
      checkInBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removeExistingMenu()
        this.openBoardOverlay("reservation-board:open-check-in", checkInUrl)
      })
    }
    
    const checkOutBtn = menu.querySelector('[data-booking-actions-target="checkOutBtn"]')
    if (this.statusValue === "checked_in") {
      checkOutBtn.classList.remove("hidden")
      checkOutBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removeExistingMenu()
        this.openBoardOverlay("reservation-board:open-check-out", checkOutUrl)
      })
    }

    const detailsBtn = menu.querySelector('[data-booking-actions-target="detailsBtn"]')
    detailsBtn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.showDetails()
    })

    const extend1Btn = menu.querySelector('[data-action="booking-actions#extend1Day"]')
    if (extend1Btn) extend1Btn.addEventListener("click", (e) => {
      e.stopPropagation()
      this.extend1Day()
    })

    const extend2Btn = menu.querySelector('[data-action="booking-actions#extend2Days"]')
    if (extend2Btn) extend2Btn.addEventListener("click", (e) => {
      e.stopPropagation()
      this.extend2Days()
    })

    document.body.appendChild(menu)

    computePosition(event.currentTarget, menu, {
      placement: 'bottom-start',
      middleware: [offset(5), flip(), shift({ padding: 5 })],
    }).then(({ x, y }) => {
      Object.assign(menu.style, {
        position: 'absolute',
        left: `${x}px`,
        top: `${y + window.scrollY}px`,
      })
    })
  }

  openNotes(event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    this.removeExistingMenu()

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/notes`
    this.openBoardOverlay("reservation-board:open-notes", url, "reservation_board_notes_content")
  }

  showDetails() {
    this.removeExistingMenu()
    const hotelId = window.location.pathname.split('/')[2]
    const detailsUrl = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}`
    this.openBoardOverlay("reservation-board:open-booking-sheet", detailsUrl, "reservation_board_booking_sheet_content")
  }

  openCheckIn(event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    const url = event?.currentTarget?.dataset.bookingActionsUrlValue || `/hotel/${window.location.pathname.split('/')[2]}/reservation-board/bookings/${this.idValue}/check_in`
    this.openBoardOverlay("reservation-board:open-check-in", url, "reservation_board_check_in_content")
  }

  openCheckOut(event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    const url = event?.currentTarget?.dataset.bookingActionsUrlValue || `/hotel/${window.location.pathname.split('/')[2]}/reservation-board/bookings/${this.idValue}/check_out`
    this.openBoardOverlay("reservation-board:open-check-out", url, "reservation_board_check_out_content")
  }

  openEditStay(event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/edit_stay`
    this.openBoardOverlay("reservation-board:open-edit-stay", url, "reservation_board_edit_stay_content")
  }

  openCentralModal(url) {
    this.openBoardOverlay("reservation-board:open-modal", url, "reservation_board_booking_sheet_content")
  }

  openBoardOverlay(eventName, url, frameId = null) {
    const event = new CustomEvent(eventName, { detail: { url, frameId } })
    window.dispatchEvent(event)
  }

  checkIn() {
    this.transitionStatus("checked_in")
  }

  checkOut() {
    if (confirm("Are you sure you want to check out this guest?")) {
      this.transitionStatus("completed")
    }
  }

  extend1Day() {
    this.extendStay(1)
  }

  extend2Days() {
    this.extendStay(2)
  }

  extendStay(days) {
    if (!this.checkOutValue) return
    const currentCheckOut = new Date(this.checkOutValue)
    const newCheckOut = new Date(currentCheckOut.getTime() + days * 24 * 60 * 60 * 1000)
    const newCheckOutStr = newCheckOut.toISOString().split('T')[0]

    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/bookings/${this.idValue}`

    window.dispatchEvent(new CustomEvent("reservation-board:confirm-extend", {
      detail: {
        guestName: this.guestNameValue,
        currentCheckOut: this.checkOutValue,
        newCheckOut: newCheckOutStr,
        onConfirm: () => fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          booking: { check_out: newCheckOutStr }
        })
        }).then(response => response.json()),
        onSuccess: (data) => {
          if (data.success) {
            Turbo.visit(window.location.href, { action: "replace" })
          } else {
            alert(`Failed to extend stay: ${data.errors.join(", ")}`)
          }
          this.removeExistingMenu()
        },
        onError: () => this.removeExistingMenu(),
        onCancel: () => this.removeExistingMenu()
      }
    }))
  }

  transitionStatus(status) {
    const hotelId = window.location.pathname.split('/')[2]
    const url = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}/transition`
    
    this.sendPatch(url, { status })
  }

  sendPatch(url, body) {
    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify(body)
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
    }).then(html => {
      if (html) Turbo.renderStreamMessage(html)
      this.removeExistingMenu()
    })
  }

  removeExistingMenu() {
    const menu = document.getElementById("active-booking-menu")
    if (menu) menu.remove()

    const overlay = document.getElementById("active-booking-overlay")
    if (overlay) overlay.remove()
  }

  disconnect() {
    this.removeExistingMenu()
  }
}
