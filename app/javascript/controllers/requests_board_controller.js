import { Controller } from "@hotwired/stimulus"

// The board's gestures: moving a card to a lane, and reordering the lanes.
//
// It decides nothing about what a move means. A drop reports which card went
// where and the server answers with the two lanes that changed, so a card
// dragged to a lane and the button on that card cannot come to disagree.
const EDGE_ZONE = 96
const EDGE_STEP = 24
const REORDER_TARGET_CLASSES = ["ring-2", "ring-inset", "ring-border-interactive"]
const AVAILABLE_TARGET_CLASSES = ["ring-2", "ring-inset", "ring-success"]
const VALID_ACTIVE_CLASSES = ["bg-success/10"]
const INVALID_ACTIVE_CLASSES = ["outline", "outline-2", "-outline-offset-2", "outline-destructive", "bg-destructive/10"]

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
    this.showCardDropTargets(this.draggedCard)
  }

  dragEnd() {
    this.draggedCard?.removeAttribute("aria-grabbed")
    this.stopAutoScroll()
    this.clearHighlights()
    this.draggedCard = null
  }

  dragOver(event) {
    event.preventDefault()
    const column = event.currentTarget

    if (this.draggedColumn) {
      column.classList.add(...REORDER_TARGET_CLASSES)
    } else if (this.draggedCard) {
      const classes = this.validDropTarget(this.draggedCard, column) ? VALID_ACTIVE_CLASSES : INVALID_ACTIVE_CLASSES
      column.classList.add(...classes)
    }

    // A lane the pointer cannot reach is a lane a card cannot be dropped in, and
    // most of them are off-screen once the board scrolls sideways.
    this.autoScrollToward(event.clientX)
  }

  dragLeave(event) {
    const classes = this.draggedColumn ?
      REORDER_TARGET_CLASSES :
      [...VALID_ACTIVE_CLASSES, ...INVALID_ACTIVE_CLASSES]
    event.currentTarget.classList.remove(...classes)
  }

  async drop(event) {
    event.preventDefault()

    const column = event.currentTarget
    const classes = this.draggedColumn ?
      REORDER_TARGET_CLASSES :
      [...VALID_ACTIVE_CLASSES, ...INVALID_ACTIVE_CLASSES]
    column.classList.remove(...classes)
    this.stopAutoScroll()

    if (this.draggedColumn) {
      this.reorderColumns(column)
      this.persistColumnOrder()
      this.columnDragEnd()
      return
    }

    if (!this.draggedCard) return

    const card = this.draggedCard
    this.dragEnd()
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
    const direction = event.key === "ArrowRight" ? 1 : -1
    const next = this.nextValidColumn(this.carriedTarget, card, direction)
    if (!next) return

    this.carriedTarget = next
    this.highlightCarriedTarget()
  }

  carry(card) {
    this.carriedCard = card
    this.carriedTarget = card.closest('[data-requests-board-target="column"]')
    card.setAttribute("aria-grabbed", "true")
    this.showCardDropTargets(card)
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
    this.clearActiveHighlights()
    if (this.validDropTarget(this.carriedCard, this.carriedTarget)) {
      this.carriedTarget.classList.add(...VALID_ACTIVE_CLASSES)
    }
    this.carriedTarget?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
  }

  nextValidColumn(currentColumn, card, direction) {
    const columns = Array.from(this.columnTargets)
    let index = columns.indexOf(currentColumn) + direction

    while (index >= 0 && index < columns.length) {
      if (this.validDropTarget(card, columns[index])) return columns[index]
      index += direction
    }

    return null
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
    this.clearHighlights()
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
      column.classList.remove(
        ...REORDER_TARGET_CLASSES,
        ...AVAILABLE_TARGET_CLASSES,
        ...VALID_ACTIVE_CLASSES,
        ...INVALID_ACTIVE_CLASSES
      )

      const hint = column.querySelector("[data-requests-board-drop-hint]")
      if (hint) {
        hint.hidden = true
        hint.textContent = ""
        hint.dataset.variant = "neutral"
      }
    })
  }

  clearActiveHighlights() {
    this.columnTargets.forEach((column) => {
      column.classList.remove(...VALID_ACTIVE_CLASSES, ...INVALID_ACTIVE_CLASSES)
    })
  }

  showCardDropTargets(card) {
    this.clearHighlights()

    this.columnTargets.forEach((column) => {
      const valid = this.validDropTarget(card, column)
      const current = column.dataset.boardColumn === card.dataset.cardColumn
      const hint = column.querySelector("[data-requests-board-drop-hint]")

      if (valid) column.classList.add(...AVAILABLE_TARGET_CLASSES)
      if (!hint) return

      hint.textContent = this.dropHintLabel(column, { valid, current })
      hint.dataset.variant = valid ? "success" : (current ? "neutral" : "destructive")
      hint.hidden = false
    })
  }

  validDropTarget(card, column) {
    if (!card || !column) return false
    if (column.dataset.boardColumn === card.dataset.cardColumn) return false

    const acceptedKinds = (column.dataset.acceptedRequestKinds || "").split(" ").filter(Boolean)
    return acceptedKinds.includes("*") || acceptedKinds.includes(card.dataset.requestKind)
  }

  dropHintLabel(column, { valid, current }) {
    if (current) return "Current lane"
    if (!valid) return "Not allowed"

    switch (column.dataset.boardColumn) {
      case "completed": return "Drop to complete"
      case "archived": return "Drop to archive"
      default: return "Move here"
    }
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
