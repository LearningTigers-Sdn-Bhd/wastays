import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "roomType", "row", "checkbox", "empty", "count"]

  connect() {
    if (!this.hasSearchTarget) return

    this.filter()
    this.updateCount()
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    const roomTypeId = this.roomTypeTarget.querySelector("select")?.value || ""
    let visibleCount = 0

    this.rowTargets.forEach((row) => {
      const matchesQuery = !query || row.dataset.roomGroupRoomsSearchValue.includes(query)
      const matchesRoomType = !roomTypeId || row.dataset.roomGroupRoomsRoomTypeValue === roomTypeId
      const visible = matchesQuery && matchesRoomType
      row.classList.toggle("hidden", !visible)
      if (visible) visibleCount += 1
    })

    this.emptyTarget.classList.toggle("hidden", visibleCount > 0)
  }

  updateCount() {
    if (!this.hasCountTarget) return

    const count = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    this.countTarget.textContent = `${count} ${count === 1 ? "room" : "rooms"} selected`
  }
}
