import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  open(event) {
    const { date, roomNumber, roomTypeId } = event.params
    const hotelId = window.location.pathname.split('/')[2]
    
    const params = new URLSearchParams(window.location.search)
    params.set("room_number", roomNumber)
    params.set("room_type_id", roomTypeId)
    params.set("start_date", date)
    
    const url = `/hotel/${hotelId}/room_blocks/new?${params.toString()}`
    this.triggerOffcanvas(url, "compact-right")
  }

  edit(event) {
    const { id } = event.params
    const hotelId = window.location.pathname.split('/')[2]
    
    const params = new URLSearchParams(window.location.search)
    const url = `/hotel/${hotelId}/room_blocks/${id}/edit?${params.toString()}`
    this.triggerOffcanvas(url, "compact-right")
  }

  triggerOffcanvas(url, variant = "right") {
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
