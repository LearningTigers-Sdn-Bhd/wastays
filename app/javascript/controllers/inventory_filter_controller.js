import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["category", "roomRow"]

  connect() {
    this.filter()
  }

  filter() {
    // Get array of IDs for checked categories
    const selectedTypeIds = Array.from(this.categoryTargets)
      .filter(cb => cb.checked)
      .map(cb => cb.value)

    this.roomRowTargets.forEach(row => {
      const roomTypeId = row.dataset.roomTypeId
      
      // LOGIC: 
      // 1. If NO categories are checked, show ALL rooms.
      // 2. If SOME categories are checked, only show rooms belonging to those categories.
      const shouldShow = (selectedTypeIds.length === 0 || selectedTypeIds.includes(roomTypeId))
      
      if (shouldShow) {
        row.classList.remove("hidden")
      } else {
        row.classList.add("hidden")
        // Uncheck hidden rooms so they are not accidentally applied to inventory
        const checkbox = row.querySelector("input[type='checkbox']")
        if (checkbox) checkbox.checked = false
      }
    })
  }
}
