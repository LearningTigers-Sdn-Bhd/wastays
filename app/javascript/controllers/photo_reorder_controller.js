import { Controller } from "@hotwired/stimulus"

// Drag-and-drop ordering for a photo album grid — the Hotel Album page and the
// room category sheet both use it. The order is staged in the browser and
// written to a hidden field, so Save Order and Cancel decide whether it reaches
// the database. Nothing persists on drop.
//
// The controller owns Save and Cancel itself rather than leaving them to
// form-dirty. In the room category sheet the save form sits outside the grid —
// a form inside the category form would end it early — and a controller on that
// form could not reach buttons drawn beside the tiles.
//
// The featured photo is pinned to the front. It carries no drag handle, and no
// other tile can move ahead of it — a refused move says so with a toast rather
// than snapping the tile back without a word.
export default class extends Controller {
  static targets = ["grid", "input", "pinned", "submit", "cancel"]

  connect() {
    this.snapshot = this.orderedIds()
    this.dragged = null
    this.refresh()
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
    this.inputTarget.value = this.orderedIds()
    this.refresh()
  }

  // Cancel puts the tiles back in their saved order. Save and Cancel both start
  // switched off, because a grid that has just loaded has nothing to save and
  // nothing to discard.
  reset() {
    this.snapshot.split(",").filter(Boolean).forEach((id) => {
      const tile = this.gridTarget.querySelector(`[data-photo-id="${id}"]`)
      if (tile) this.gridTarget.appendChild(tile)
    })

    this.commitOrder()
  }

  refresh() {
    const changed = this.orderedIds() !== this.snapshot

    this.submitTargets.forEach((button) => { button.disabled = !changed })
    this.cancelTargets.forEach((button) => { button.hidden = !changed })
  }

  orderedIds() {
    return Array.from(this.gridTarget.querySelectorAll("[data-photo-id]"))
      .map((tile) => tile.dataset.photoId)
      .join(",")
  }
}
