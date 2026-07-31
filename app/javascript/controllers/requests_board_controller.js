import { Controller } from "@hotwired/stimulus"

// The board's gestures: moving a card to a lane, and reordering the lanes.
//
// It decides nothing about what a move means. A drop reports which card went
// where and the server answers with the two lanes that changed, so a card
// dragged to a lane and the button on that card cannot come to disagree.
const EDGE_ZONE = 96
const EDGE_STEP = 24

export default class extends Controller {
  static targets = ["board", "card", "column"]
  static values = { hotelId: Number }

  connect() {
    this.draggedCard = null
    this.draggedColumn = null
    this.carriedCard = null
    this.autoScroll = null
    this.restoreColumnOrder()
  }

  disconnect() {
    this.stopAutoScroll()
  }

  // -- Moving a card -------------------------------------------------------

  dragStart(event) {
    this.draggedColumn = null
    this.draggedCard = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedCard.dataset.requestId)
    this.draggedCard.setAttribute("aria-grabbed", "true")
  }

  dragEnd() {
    this.draggedCard?.removeAttribute("aria-grabbed")
    this.stopAutoScroll()
    this.clearHighlights()
    this.draggedCard = null
  }

  dragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-border-interactive")
    // A lane the pointer cannot reach is a lane a card cannot be dropped in, and
    // most of them are off-screen once the board scrolls sideways.
    this.autoScrollToward(event.clientX)
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-border-interactive")
  }

  async drop(event) {
    event.preventDefault()

    const column = event.currentTarget
    column.classList.remove("ring-2", "ring-border-interactive")
    this.stopAutoScroll()

    if (this.draggedColumn) {
      this.reorderColumns(column)
      this.persistColumnOrder()
      this.columnDragEnd()
      return
    }

    if (!this.draggedCard) return

    const card = this.draggedCard
    this.draggedCard = null
    await this.move(card, column)
  }

  // -- Keyboard ------------------------------------------------------------
  //
  // Pick a card up with Enter or Space, walk it with the arrows, drop it with
  // Enter or Space again, give up with Escape. Dragging is a mouse gesture and
  // this board is a working queue, so it cannot be the only way to move a card.

  cardKeydown(event) {
    const card = event.currentTarget

    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.carriedCard === card ? this.dropCarried(card) : this.carry(card)
      return
    }

    if (event.key === "Escape" && this.carriedCard === card) {
      event.preventDefault()
      this.release(card)
      return
    }

    if (this.carriedCard !== card) return
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return

    event.preventDefault()
    const columns = this.droppableColumns()
    const current = columns.indexOf(this.carriedTarget)
    const next = event.key === "ArrowRight" ? current + 1 : current - 1
    if (next < 0 || next >= columns.length) return

    this.carriedTarget = columns[next]
    this.highlightCarriedTarget()
  }

  carry(card) {
    this.carriedCard = card
    this.carriedTarget = card.closest('[data-requests-board-target="column"]')
    card.setAttribute("aria-grabbed", "true")
    this.highlightCarriedTarget()
  }

  release(card) {
    card.removeAttribute("aria-grabbed")
    this.carriedCard = null
    this.carriedTarget = null
    this.clearHighlights()
  }

  async dropCarried(card) {
    const target = this.carriedTarget
    this.release(card)
    if (target) await this.move(card, target)
  }

  highlightCarriedTarget() {
    this.clearHighlights()
    this.carriedTarget?.classList.add("ring-2", "ring-border-interactive")
    this.carriedTarget?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
  }

  droppableColumns() {
    return Array.from(this.columnTargets).filter((column) => column.dataset.moveUrl)
  }

  // -- Asking for the move -------------------------------------------------

  async move(card, column) {
    const moveUrl = column.dataset.moveUrl
    if (!moveUrl) return
    if (column.dataset.boardColumn === card.dataset.cardColumn) return

    const body = new FormData()
    body.append("kind", card.dataset.recordKind)
    body.append("display_kind", card.dataset.requestKind)
    body.append("request_id", card.dataset.requestId)

    const response = await fetch(moveUrl, {
      method: "PATCH",
      headers: { "X-CSRF-Token": this.csrfToken, Accept: "text/vnd.turbo-stream.html" },
      body
    })

    // Both outcomes are a stream: the move, or the reason it was refused.
    const stream = await response.text()
    if (stream.trim()) window.Turbo.renderStreamMessage(stream)
  }

  // -- Reaching an off-screen lane -----------------------------------------

  autoScrollToward(clientX) {
    const viewport = this.scrollViewport()
    if (!viewport) return

    const bounds = viewport.getBoundingClientRect()
    let step = 0
    if (clientX < bounds.left + EDGE_ZONE) step = -EDGE_STEP
    if (clientX > bounds.right - EDGE_ZONE) step = EDGE_STEP

    if (step === 0) return this.stopAutoScroll()
    if (this.autoScroll) return

    this.autoScroll = window.setInterval(() => viewport.scrollBy({ left: step }), 16)
  }

  stopAutoScroll() {
    if (!this.autoScroll) return

    window.clearInterval(this.autoScroll)
    this.autoScroll = null
  }

  scrollViewport() {
    return this.element.closest(".panel-scroll-area__viewport") ||
      this.boardTarget.closest(".panel-scroll-area__viewport")
  }

  // -- Reordering the lanes ------------------------------------------------

  columnDragStart(event) {
    this.draggedCard = null
    this.draggedColumn = event.currentTarget.closest('[data-requests-board-target="column"]')

    if (!this.draggedColumn) return

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedColumn.dataset.boardColumn)
    this.draggedColumn.classList.add("opacity-60")
  }

  columnDragEnd() {
    this.draggedColumn?.classList.remove("opacity-60")
    this.stopAutoScroll()
    this.clearHighlights()
    this.draggedColumn = null
  }

  columnKeydown(event) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return

    const column = event.currentTarget.closest('[data-requests-board-target="column"]')
    const columns = Array.from(this.columnTargets)
    const index = columns.indexOf(column)
    const next = event.key === "ArrowRight" ? index + 1 : index - 1
    if (index === -1 || next < 0 || next >= columns.length) return

    event.preventDefault()
    this.draggedColumn = column
    this.reorderColumns(columns[next])
    this.persistColumnOrder()
    this.draggedColumn = null
    event.currentTarget.focus()
    column.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
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

  clearHighlights() {
    this.columnTargets.forEach((column) => {
      column.classList.remove("ring-2", "ring-border-interactive")
    })
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
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
