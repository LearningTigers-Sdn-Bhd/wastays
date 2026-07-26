import { Controller } from "@hotwired/stimulus"

// Drag-and-drop reordering for the superadmin "Booking Sources" list. Each
// category (Manual, OTA, etc.) is its own drop target — rows can only be
// reordered within their own category list, matching how they group in the
// manual source dropdown. Persists the new order on drop.
export default class extends Controller {
  static targets = ["list"]

  dragStart(event) {
    this.dragged = event.currentTarget
    this.originList = this.dragged.closest('[data-booking-source-reorder-target="list"]')
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.id)
    this.dragged.classList.add("opacity-50")
  }

  dragEnd() {
    if (this.dragged) this.dragged.classList.remove("opacity-50")
    this.dragged = null
    this.originList = null
  }

  dragOver(event) {
    if (!this.dragged) return

    const row = event.currentTarget
    const list = row.closest('[data-booking-source-reorder-target="list"]')
    if (!list || list !== this.originList || row === this.dragged) return

    event.preventDefault()
    const rect = row.getBoundingClientRect()
    const before = event.clientY - rect.top < rect.height / 2
    list.insertBefore(this.dragged, before ? row : row.nextElementSibling)
  }

  async drop(event) {
    event.preventDefault()
    if (!this.dragged) return

    const list = this.originList
    this.dragEnd()
    if (!list) return

    const orderedIds = Array.from(list.querySelectorAll("[data-id]")).map((row) => row.dataset.id)

    await fetch(list.dataset.reorderUrl, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ kind: list.dataset.kind, ordered_ids: orderedIds })
    })
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
