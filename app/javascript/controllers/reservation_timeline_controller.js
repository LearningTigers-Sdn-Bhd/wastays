import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "dragHandle", "resizeHandle"]

  connect() {
    this.draggedElement = null
    this.isResizing = false
    this.canDrag = false
  }

  openNewBookingModal(event) {
    event.preventDefault()
    const url = event.currentTarget.href
    const container = document.getElementById("reservation-board-action-modal-container")
    if (container) {
      const modalEvent = new CustomEvent("reservation-board:open-modal", { detail: { url } })
      container.dispatchEvent(modalEvent)
    }
  }

  onDragHandleMouseDown(event) {
    this.canDrag = true
  }

  onResizeStart(event) {
    event.stopPropagation()
    event.preventDefault()
    this.isResizing = true
    this.draggedElement = event.currentTarget.closest('[data-id]')
    this.draggedElement.draggable = false // Disable drag while resizing
    
    this.originalWidth = this.draggedElement.offsetWidth
    this.originalWidthStyle = this.draggedElement.style.width // Store original inline style
    this.startX = event.clientX
    
    this.boundOnResizing = this.onResizing.bind(this)
    this.boundOnResizeEnd = this.onResizeEnd.bind(this)
    
    document.addEventListener("mousemove", this.boundOnResizing)
    document.addEventListener("mouseup", this.boundOnResizeEnd)
    
    this.draggedElement.classList.add("ring-2", "ring-blue-500", "z-50")
  }

  onResizing(event) {
    if (!this.isResizing) return
    const deltaX = event.clientX - this.startX
    this.draggedElement.style.width = `${this.originalWidth + deltaX}px`
  }

  async onResizeEnd(event) {
    if (!this.isResizing) return
    this.isResizing = false
    document.removeEventListener("mousemove", this.boundOnResizing)
    document.removeEventListener("mouseup", this.boundOnResizeEnd)
    
    this.draggedElement.classList.remove("ring-2", "ring-blue-500", "z-50")
    this.draggedElement.draggable = true
    
    // Temporarily disable pointer events to find what's underneath
    const originalPointerEvents = this.draggedElement.style.pointerEvents
    this.draggedElement.style.pointerEvents = "none"
    
    // Determine the new checkout date based on where the mouse was released
    const elementUnderMouse = document.elementFromPoint(event.clientX, event.clientY)
    const cell = elementUnderMouse?.closest('[data-reservation-timeline-target="cell"]')
    
    // Restore pointer events
    this.draggedElement.style.pointerEvents = originalPointerEvents
    
    if (cell) {
      const dropDate = new Date(cell.dataset.date)
      // The cell we drop on is the "Last Night" of the stay.
      // So the Check-out Date is the morning of the NEXT day.
      const newCheckOut = new Date(dropDate.getTime() + 24 * 60 * 60 * 1000)
      const newCheckOutStr = newCheckOut.toISOString().split('T')[0]
      const bookingId = this.draggedElement.dataset.id
      
      if (confirm(`Extend stay to checkout on ${newCheckOutStr}?`)) {
        try {
          const response = await this.resizeBooking(bookingId, newCheckOutStr)
          if (response.success) {
            Turbo.visit(window.location.href, { action: "replace" })
          } else {
            alert(`Failed to extend stay: ${response.errors.join(", ")}`)
            this.draggedElement.style.width = this.originalWidthStyle
          }
        } catch (error) {
          console.error("Error extending stay:", error)
          this.draggedElement.style.width = this.originalWidthStyle
        }
      } else {
        this.draggedElement.style.width = this.originalWidthStyle
      }
    } else {
      this.draggedElement.style.width = this.originalWidthStyle
    }
  }

  async resizeBooking(id, checkOutDate) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const hotelId = window.location.pathname.split('/')[2]
    
    const response = await fetch(`/hotel/${hotelId}/bookings/${id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        booking: { check_out: checkOutDate }
      })
    })

    return await response.json()
  }

  onDragStart(event) {
    if (this.isResizing || !this.canDrag) {
      event.preventDefault()
      this.canDrag = false
      return
    }

    this.draggedElement = event.currentTarget
    event.dataTransfer.setData("text/plain", this.draggedElement.dataset.id)
    event.dataTransfer.effectAllowed = "move"
    
    // Add a ghost effect or class
    this.draggedElement.classList.add("opacity-50")
  }

  onDragEnd(event) {
    if (this.draggedElement) {
      this.draggedElement.classList.remove("opacity-50")
    }
    this.draggedElement = null
    this.canDrag = false
  }

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("bg-blue-50")
  }

  onDragLeave(event) {
    event.currentTarget.classList.remove("bg-blue-50")
  }

  async onDrop(event) {
    event.preventDefault()
    const cell = event.currentTarget
    cell.classList.remove("bg-blue-50")
    
    const bookingId = event.dataTransfer.getData("text/plain")
    const newDateStr = cell.dataset.date
    const newRoomNumber = cell.dataset.roomNumber
    const newRoomTypeId = cell.dataset.roomTypeId

    if (!bookingId || !newDateStr || !newRoomNumber) return

    // Find the original booking to calculate duration
    const checkIn = new Date(this.draggedElement.dataset.bookingActionsCheckInValue)
    const checkOut = new Date(this.draggedElement.dataset.bookingActionsCheckOutValue)
    const durationMs = checkOut.getTime() - checkIn.getTime()
    
    const newCheckIn = new Date(newDateStr)
    const newCheckOut = new Date(newCheckIn.getTime() + durationMs)
    const newCheckOutStr = newCheckOut.toISOString().split('T')[0]
    
    if (confirm(`Move booking to ${newRoomNumber} on ${newDateStr}?`)) {
      try {
        const response = await this.moveBooking(bookingId, newDateStr, newCheckOutStr, newRoomNumber, newRoomTypeId)
        if (response.success) {
          Turbo.visit(window.location.href, { action: "replace" })
        } else {
          alert(`Failed to move booking: ${response.errors.join(", ")}`)
        }
      } catch (error) {
        console.error("Error moving booking:", error)
        alert("An unexpected error occurred while moving the booking.")
      }
    }
  }

  async moveBooking(id, checkIn, checkOut, roomNumber, roomTypeId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const hotelId = window.location.pathname.split('/')[2]
    
    const response = await fetch(`/hotel/${hotelId}/bookings/${id}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        check_in: checkIn,
        check_out: checkOut,
        room_number: roomNumber,
        room_type_id: roomTypeId
      })
    })

    return await response.json()
  }
}
