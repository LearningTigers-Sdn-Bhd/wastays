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
      openNotesBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removeExistingMenu()
        const modal = document.getElementById("reservation-board-notes-modal")
        const listContainer = document.getElementById("reservation-board-notes-list")
        if (modal && listContainer) {
          listContainer.innerHTML = ""
          try {
            const notes = JSON.parse(this.notesValue)
            notes.forEach(note => {
              const item = document.createElement("div")
              item.className = "p-4 bg-slate-50 rounded-xl border border-slate-100"
              item.innerHTML = `
                <div class="flex justify-between items-start mb-2">
                  <span class="text-xs font-bold text-slate-900">${note.author}</span>
                  <span class="text-[10px] text-slate-500 font-medium">${note.date}</span>
                </div>
                <p class="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed italic">${note.body}</p>
              `
              listContainer.appendChild(item)
            })
          } catch (err) {
            console.error("Error parsing notes:", err)
            listContainer.innerHTML = `<p class="text-sm text-slate-500 italic">${this.notesValue}</p>`
          }
          modal.showModal()
        }
      })
    }

    // Set details link
    const hotelId = window.location.pathname.split('/')[2]
    const detailsUrl = `/hotel/${hotelId}/reservation-board/bookings/${this.idValue}`
    
    // Configure buttons based on state
    const today = new Date().toISOString().split('T')[0]
    const isCheckInDay = this.checkInValue <= today && this.statusValue === "confirmed"
    const isCheckedIn = this.statusValue === "checked_in"
    
    const checkInBtn = menu.querySelector('[data-booking-actions-target="checkInBtn"]')
    if (isCheckInDay || isCheckedIn) {
      checkInBtn.classList.remove("hidden")
      if (isCheckedIn) {
        checkInBtn.innerHTML = `
          <svg class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M16.862 3.487 1.65-1.65a2.25 2.25 0 1 1 3.182 3.182l-1.65 1.65M18 5 7.5 15.5 3 21l5.5-4.5L19 6z" /></svg>
          Edit Check-In
        `
      }
      checkInBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removeExistingMenu()
        this.openCentralModal(detailsUrl)
      })
    }
    
    const checkOutBtn = menu.querySelector('[data-booking-actions-target="checkOutBtn"]')
    if (this.statusValue === "checked_in") {
      checkOutBtn.classList.remove("hidden")
      checkOutBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removeExistingMenu()
        this.openCentralModal(detailsUrl)
      })
    }

    const detailsBtn = menu.querySelector('[data-booking-actions-target="detailsBtn"]')
    detailsBtn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.removeExistingMenu()
      this.openCentralModal(detailsUrl)
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

  openCentralModal(url) {
    const container = document.getElementById("reservation-board-action-modal-container")
    if (container) {
      const event = new CustomEvent("reservation-board:open-modal", { detail: { url } })
      container.dispatchEvent(event)
    }
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

    if (confirm(`Extend stay to checkout on ${newCheckOutStr}?`)) {
      const hotelId = window.location.pathname.split('/')[2]
      const url = `/hotel/${hotelId}/bookings/${this.idValue}`
      
      fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          booking: { check_out: newCheckOutStr }
        })
      }).then(response => response.json()).then(data => {
        if (data.success) {
          Turbo.visit(window.location.href, { action: "replace" })
        } else {
          alert(`Failed to extend stay: ${data.errors.join(", ")}`)
        }
        this.removeExistingMenu()
      }).catch(error => {
        console.error("Error extending stay:", error)
        this.removeExistingMenu()
      })
    }
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
