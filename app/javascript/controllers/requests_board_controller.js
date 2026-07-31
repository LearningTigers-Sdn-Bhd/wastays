import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["board", "card", "column"]
  static values = { hotelId: Number }

  connect() {
    this.draggedCard = null
    this.draggedColumn = null
    this.restoreColumnOrder()
  }

  dragStart(event) {
    this.draggedColumn = null
    this.draggedCard = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedCard.dataset.requestId)
    this.draggedCard.classList.add("opacity-60")
  }

  dragEnd() {
    if (this.draggedCard) {
      this.draggedCard.classList.remove("opacity-60")
    }

    this.clearHighlights()
    this.draggedCard = null
  }

  columnDragStart(event) {
    this.draggedCard = null
    this.draggedColumn = event.currentTarget.closest('[data-requests-board-target="column"]')

    if (!this.draggedColumn) return

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedColumn.dataset.boardColumn)
    this.draggedColumn.classList.add("opacity-60")
  }

  columnDragEnd() {
    if (this.draggedColumn) {
      this.draggedColumn.classList.remove("opacity-60")
    }

    this.clearHighlights()
    this.draggedColumn = null
  }

  dragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-blue-200")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-blue-200")
  }

  async drop(event) {
    event.preventDefault()

    const column = event.currentTarget
    column.classList.remove("ring-2", "ring-blue-200")

    if (this.draggedColumn) {
      this.reorderColumns(column)
      this.persistColumnOrder()
      this.columnDragEnd()
      return
    }

    if (!this.draggedCard) return

    const targetColumn = column.dataset.boardColumn
    const updateUrl = this.draggedCard.dataset.updateUrl
    const currentStatus = this.draggedCard.dataset.currentStatus
    const requestKind = this.draggedCard.dataset.requestKind
    const targetStatus = this.targetStatusFor(targetColumn, requestKind)

    if (!targetStatus || targetStatus === currentStatus) {
      this.draggedCard.classList.remove("opacity-60")
      this.draggedCard = null
      return
    }

    const response = await fetch(updateUrl, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ status: targetStatus })
    })

    if (response.ok) {
      window.location.reload()
    } else {
      this.draggedCard.classList.remove("opacity-60")
    }

    this.draggedCard = null
  }

  clearHighlights() {
    this.columnTargets.forEach((column) => {
      column.classList.remove("ring-2", "ring-blue-200")
    })
  }

  reorderColumns(targetColumn) {
    if (!this.draggedColumn || this.draggedColumn === targetColumn) return

    const board = this.boardTarget
    const columns = Array.from(this.columnTargets)
    const draggedIndex = columns.indexOf(this.draggedColumn)
    const targetIndex = columns.indexOf(targetColumn)

    if (draggedIndex === -1 || targetIndex === -1) return

    if (draggedIndex < targetIndex) {
      board.insertBefore(this.draggedColumn, targetColumn.nextElementSibling)
    } else {
      board.insertBefore(this.draggedColumn, targetColumn)
    }
  }

  targetStatusFor(column, requestKind) {
    if (column === "completed") {
      return requestKind === "complaint" ? "resolved" : "completed"
    }

    if (column === "housekeeping" && requestKind === "housekeeping") {
      return "pending"
    }

    if (column === "complaint" && requestKind === "complaint") {
      return "pending"
    }

    return null
  }

  persistColumnOrder() {
    if (!this.hasHotelIdValue) return

    const order = Array.from(this.boardTarget.querySelectorAll('[data-requests-board-target="column"]'))
      .map((column) => column.dataset.boardColumn)

    window.localStorage.setItem(this.storageKey, JSON.stringify(order))
  }

  restoreColumnOrder() {
    if (!this.hasHotelIdValue) return

    const raw = window.localStorage.getItem(this.storageKey)
    if (!raw) return

    let order
    try {
      order = JSON.parse(raw)
    } catch {
      return
    }

    if (!Array.isArray(order)) return

    // Appending only the stored columns leaves any the order predates -- a column
    // added since it was saved -- ahead of all of them. Every column is placed,
    // the stored ones in their order and the rest after, in the order rendered.
    const columns = Array.from(this.columnTargets)
    const stored = order
      .map((key) => columns.find((column) => column.dataset.boardColumn === key))
      .filter(Boolean)

    stored.concat(columns.filter((column) => !stored.includes(column)))
      .forEach((column) => this.boardTarget.appendChild(column))
  }

  get storageKey() {
    return `requests_board_order_${this.hotelIdValue}`
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
