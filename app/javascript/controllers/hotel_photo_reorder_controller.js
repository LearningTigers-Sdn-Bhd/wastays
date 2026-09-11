import { Controller } from "@hotwired/stimulus"

// Drag-and-drop ordering for the Hotel Album grid. The order is staged in the
// browser and written to a hidden field, so the album's own Save and Cancel
// buttons decide whether it reaches the database. Nothing persists on drop.
//
// The featured photo is pinned to the front. It carries no drag handle, and no
// other tile can move ahead of it — a refused move says so with a toast rather
// than snapping the tile back without a word.
export default class extends Controller {
  static targets = ["grid", "input", "pinned"]

  connect() {
    this.snapshot = this.orderedIds()
    this.dragged = null
    // The reset comes from the footer form, which is a sibling of the grid: a
    // photo's Remove action is a button_to, and a form inside a form ends the
    // outer one early.
    this.element.addEventListener("reset", this.boundReset = () => this.reset())
  }

  disconnect() {
    this.element.removeEventListener("reset", this.boundReset)
  }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragged.dataset.photoId)
    this.dragged.dataset.dragging = "true"
    this.refusedThisDrag = false
  }

  dragEnd() {
    if (this.dragged) delete this.dragged.dataset.dragging
    this.dragged = null
    this.commitOrder()
  }

  dragOver(event) {
    if (!this.dragged) return

    const tile = event.currentTarget
    if (tile === this.dragged) return

    event.preventDefault()

    const rect = tile.getBoundingClientRect()
    const before = event.clientX - rect.left < rect.width / 2

    if (this.hasPinnedTarget && tile === this.pinnedTarget && before) {
      this.refuseMove()
      return
    }

    this.gridTarget.insertBefore(this.dragged, before ? tile : tile.nextElementSibling)
  }

  drop(event) {
    event.preventDefault()
    this.dragEnd()
  }

  // A dragover fires many times per second. Announcing the pinned photo once
  // per drag keeps one refused move from stacking up a wall of toasts.
  refuseMove() {
    if (this.refusedThisDrag) return

    this.refusedThisDrag = true
    window.toast?.("The featured photo always stays first.", { type: "info" })
  }

  commitOrder() {
    const ordered = this.orderedIds()
    if (ordered === this.inputTarget.value) return

    this.inputTarget.value = ordered
    // The album's dirty check reads the form, so the hidden field has to
    // announce itself the way a typed field would.
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Cancel resets the form, which restores the hidden field but leaves the
  // tiles where the drag put them. Put them back in their saved order.
  reset() {
    requestAnimationFrame(() => {
      this.snapshot.split(",").filter(Boolean).forEach((id) => {
        const tile = this.gridTarget.querySelector(`[data-photo-id="${id}"]`)
        if (tile) this.gridTarget.appendChild(tile)
      })

      this.inputTarget.value = this.snapshot
      // The dirty check reads the form a frame after the reset too. Announcing
      // the restored value keeps the footer honest whichever frame wins.
      this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    })
  }

  orderedIds() {
    return Array.from(this.gridTarget.querySelectorAll("[data-photo-id]"))
      .map((tile) => tile.dataset.photoId)
      .join(",")
  }
}
