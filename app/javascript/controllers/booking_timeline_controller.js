import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "dragHandle", "resizeHandle"]

  connect() {
    this.draggedElement = null
    this.isResizing = false
    this.canDrag = false
  }

  onDragHandleMouseDown(event) {
    event.stopPropagation()
    this.canDrag = true
  }

  onHandleClick(event) {
    event.preventDefault()
    event.stopPropagation()
  }

  onResizeStart(event) {
    event.stopPropagation()
    event.preventDefault()
    this.isResizing = true
    this.draggedElement = event.currentTarget.closest('[data-id]')
    if (!this.draggedElement) {
      this.isResizing = false
      return
    }
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
    const cell = elementUnderMouse?.closest('[data-booking-timeline-target="cell"]')
    
    // Restore pointer events
    this.draggedElement.style.pointerEvents = originalPointerEvents
    
    if (cell) {
      const dropDate = new Date(cell.dataset.date)
      // The cell we drop on is the "Last Night" of the stay.
      // So the Check-out Date is the morning of the NEXT day.
      const newCheckOut = new Date(dropDate.getTime() + 24 * 60 * 60 * 1000)
      const newCheckOutStr = newCheckOut.toISOString().split('T')[0]
      const bookingId = this.draggedElement.dataset.id
      
      const currentCheckOut = this.draggedElement.dataset.bookingActionsCheckOutValue
      this.draggedElement.style.width = this.originalWidthStyle

      if (newCheckOutStr !== currentCheckOut) {
        this.openTimelineSheet(bookingId, "extend", { check_out: newCheckOutStr })
      }
    } else {
      this.draggedElement.style.width = this.originalWidthStyle
    }
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

  onDrop(event) {
    event.preventDefault()
    const cell = event.currentTarget
    cell.classList.remove("bg-blue-50")
    
    const bookingId = event.dataTransfer.getData("text/plain")
    const newDateStr = cell.dataset.date
    const newRoomNumber = cell.dataset.roomNumber
    const newRoomTypeId = cell.dataset.roomTypeId

    if (!bookingId || !newDateStr || !newRoomNumber) return

    this.openTimelineSheet(bookingId, "move", {
      check_in: newDateStr,
      room_number: newRoomNumber,
      room_type_id: newRoomTypeId
    })
  }

  openTimelineSheet(id, timelineAction, proposal) {
    const hotelId = window.location.pathname.split('/')[2]
    const query = new URLSearchParams({
      timeline_action: timelineAction,
      source: "booking_timeline_board",
      return_to: `${window.location.pathname}${window.location.search}`,
      ...proposal
    })
    const link = document.createElement("a")

    link.href = `/hotel/${hotelId}/booking-transactions/edit-booking-timeline/${id}?${query}`
    link.setAttribute("data-turbo-frame", "offcanvas_drawer")
    link.setAttribute("data-offcanvas-variant", "right")
    link.hidden = true
    document.body.appendChild(link)
    link.click()
    link.remove()
  }
}
