import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]

  toggle(event) {
    const roomTypeId = event.currentTarget.dataset.roomTypeId
    const isCollapsed = event.currentTarget.dataset.collapsed === "true"
    
    // Toggle button state
    event.currentTarget.dataset.collapsed = !isCollapsed
    const icon = event.currentTarget.querySelector("svg")
    if (icon) {
      icon.style.transform = isCollapsed ? "rotate(0deg)" : "rotate(-90deg)"
    }

    // Toggle visibility of sub-rows
    this.rowTargets.forEach(row => {
      if (row.dataset.parentRoomTypeId === roomTypeId) {
        row.classList.toggle("hidden", !isCollapsed)
      }
    })
  }
}
