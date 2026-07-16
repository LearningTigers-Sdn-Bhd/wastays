import { Controller } from "@hotwired/stimulus"

const DAY_MS = 86_400_000

export default class extends Controller {
  static targets = ["segment", "row", "cell", "handle", "live"]
  static values = {
    longPress: { type: Number, default: 350 },
    dragThreshold: { type: Number, default: 6 },
    touchTolerance: { type: Number, default: 8 },
    drawerId: { type: String, default: "offcanvas_drawer" }
  }

  connect() {
    this.lifecycle = new AbortController()
    this.element.addEventListener("click", (event) => this.captureClick(event), {
      capture: true,
      signal: this.lifecycle.signal
    })
    this.element.addEventListener("dragstart", (event) => event.preventDefault(), { signal: this.lifecycle.signal })
    this.element.addEventListener("contextmenu", (event) => this.preventTouchMenu(event), { signal: this.lifecycle.signal })
    this.createLiveRegion()
  }

  disconnect() {
    this.lifecycle?.abort()
    this.cancel()
    window.clearTimeout(this.suppressClickTimer)
    this.liveRegion?.remove()
  }

  start(event) {
    if (event.button !== 0 || !event.isPrimary) return
    if (event.target.closest(".popover")) return

    const segment = event.currentTarget
    const edge = event.target.closest("[data-resize-edge]")?.dataset.resizeEdge
    const mode = edge ? "resize" : "move"
    if (mode === "move" && !segment.dataset.moveUrl) return
    if (mode === "resize" && !segment.dataset.datesUrl) return

    this.cancel()
    this.pending = {
      segment,
      edge,
      mode,
      pointerId: event.pointerId,
      pointerType: event.pointerType,
      startX: event.clientX,
      startY: event.clientY,
      startScrollLeft: this.element.scrollLeft,
      startScrollTop: this.element.scrollTop,
      lastX: event.clientX,
      lastY: event.clientY
    }
    this.installPointerListeners()

    if (event.pointerType === "touch") {
      this.longPressTimer = window.setTimeout(() => this.activate(), this.longPressValue)
    }
  }

  move(event) {
    const interaction = this.active || this.pending
    if (!interaction || event.pointerId !== interaction.pointerId) return

    interaction.lastX = event.clientX
    interaction.lastY = event.clientY
    const distance = Math.hypot(event.clientX - interaction.startX, event.clientY - interaction.startY)

    if (this.pending) {
      if (interaction.pointerType === "touch") {
        if (distance > this.touchToleranceValue) this.cancelPending()
        return
      }
      if (distance < this.dragThresholdValue) return
      this.activate()
    }

    if (!this.active) return
    event.preventDefault()
    this.updateProposal(event.clientX, event.clientY)
  }

  finish(event) {
    const interaction = this.active || this.pending
    if (!interaction || event.pointerId !== interaction.pointerId) return

    if (!this.active) {
      this.cancelPending()
      return
    }

    event.preventDefault()
    const proposal = this.active.proposal
    const segment = this.active.segment
    this.suppressNextClick = true
    window.clearTimeout(this.suppressClickTimer)
    this.suppressClickTimer = window.setTimeout(() => { this.suppressNextClick = false }, 500)
    this.cleanupInteraction()

    if (!proposal?.valid || proposal.noop) {
      this.announce(proposal?.noop ? "Booking placement unchanged." : "Booking proposal cancelled.")
      return
    }

    this.openProposal(segment, proposal)
  }

  cancel(event) {
    if (event?.key && event.key !== "Escape") return
    if (!this.active && !this.pending) return
    event?.preventDefault()
    this.cleanupInteraction()
    this.announce("Booking proposal cancelled.")
  }

  activate() {
    if (!this.pending) return

    window.clearTimeout(this.longPressTimer)
    this.active = this.pending
    this.pending = null
    const { segment, mode, pointerId, lastX, lastY } = this.active
    try { segment.setPointerCapture(pointerId) } catch (_) { /* Pointer capture is an enhancement. */ }

    segment.dataset.interacting = "true"
    this.element.dataset.interactionState = mode
    this.closeSegmentPopover(segment)
    window.dispatchEvent(new CustomEvent("panels-ui:layer-open"))
    this.createGhost(segment)
    this.updateProposal(lastX, lastY)
    this.startAutoScroll()
    this.announce(mode === "move" ? "Moving booking. Drag to a room and date, then release." : "Resizing booking. Drag the edge to a date, then release.")
  }

  updateProposal(clientX, clientY) {
    if (!this.active) return

    const dayWidth = this.dayWidth
    if (!dayWidth) return
    const horizontalDistance = clientX - this.active.startX + this.element.scrollLeft - this.active.startScrollLeft
    let dayDelta = Math.round(horizontalDistance / dayWidth)
    let checkIn = this.active.segment.dataset.checkIn
    let checkOut = this.active.segment.dataset.checkOut
    let row = this.active.segment.closest("[data-stay-view--interaction-target~='row']")

    if (this.active.mode === "move") {
      row = this.rowAt(clientX, clientY)
      checkIn = shiftDate(checkIn, dayDelta)
      checkOut = shiftDate(checkOut, dayDelta)
    } else if (this.active.edge === "start") {
      dayDelta = Math.min(dayDelta, daysBetween(checkIn, checkOut) - 1)
      checkIn = shiftDate(checkIn, dayDelta)
    } else {
      dayDelta = Math.max(dayDelta, -(daysBetween(checkIn, checkOut) - 1))
      checkOut = shiftDate(checkOut, dayDelta)
    }

    const geometry = this.geometryFor(checkIn, checkOut)
    const valid = Boolean(row && geometry)
    const originalRow = this.active.segment.closest("[data-stay-view--interaction-target~='row']")
    const noop = this.active.mode === "move"
      ? dayDelta === 0 && row === originalRow
      : dayDelta === 0

    this.active.proposal = {
      valid,
      noop,
      checkIn,
      checkOut,
      row,
      roomTypeId: row?.dataset.roomTypeId,
      roomNumber: row?.dataset.roomNumber
    }
    this.renderProposal(row, geometry, valid)
  }

  renderProposal(row, geometry, valid) {
    this.rowTargets.forEach((candidate) => delete candidate.dataset.dropTarget)
    if (row) row.dataset.dropTarget = valid ? "active" : "invalid"

    this.ghost.dataset.valid = valid.toString()
    if (!row || !geometry) return

    const track = row.querySelector(".panel-timeline__row-track")
    if (this.ghost.parentElement !== track) track.append(this.ghost)
    this.ghost.style.gridColumn = `${geometry.startTrack} / ${geometry.endTrack}`
  }

  geometryFor(checkIn, checkOut) {
    const dates = this.cellTargets.slice(0, this.dayCount).map((cell) => cell.dataset.date)
    if (dates.length === 0) return null

    const windowStart = dates[0]
    const windowEnd = shiftDate(windowStart, dates.length)
    if (checkIn >= windowEnd || checkOut <= windowStart) return null

    const startOffset = daysBetween(windowStart, checkIn)
    const endOffset = daysBetween(windowStart, checkOut)
    return {
      startTrack: startOffset < 0 ? 1 : (startOffset * 2) + 2,
      endTrack: endOffset >= dates.length ? (dates.length * 2) + 1 : (endOffset * 2) + 2
    }
  }

  rowAt(clientX, clientY) {
    const element = document.elementFromPoint(clientX, clientY)
    return element?.closest("[data-stay-view--interaction-target~='row']") || null
  }

  createGhost(segment) {
    this.ghost = document.createElement("div")
    this.ghost.className = "panel-timeline__segment panel-timeline__segment-proposal"
    this.ghost.dataset.tone = segment.dataset.tone
    this.ghost.dataset.valid = "true"
    const content = document.createElement("span")
    content.className = "panel-timeline__segment-content gap-2"
    const sourceParts = [...segment.querySelectorAll(".panel-timeline__segment-content > span")]
      .map((part) => part.textContent.trim())
      .filter(Boolean)
    const label = document.createElement("span")
    label.className = "min-w-0 flex-1 truncate"
    label.textContent = sourceParts[0] || "Booking proposal"
    content.append(label)
    if (sourceParts[1]) {
      const status = document.createElement("span")
      status.className = "shrink-0 text-xs font-medium"
      status.textContent = sourceParts[1]
      content.append(status)
    }
    this.ghost.append(content)
  }

  closeSegmentPopover(segment) {
    const controller = window.Stimulus?.getControllerForElementAndIdentifier(segment, "panels-ui--popover")
    controller?.close()
  }

  openProposal(segment, proposal) {
    const baseUrl = this.activeBaseUrl(segment, proposal)
    if (!baseUrl) return

    const url = new URL(baseUrl, window.location.origin)
    url.searchParams.set("booking[check_in]", proposal.checkIn)
    if (this.lastMode === "move") {
      url.searchParams.set("booking[room_assignment]", `${proposal.roomTypeId}|${proposal.roomNumber}`)
    } else {
      url.searchParams.set("booking[check_out]", proposal.checkOut)
    }

    const returnFocusId = `${segment.id}-trigger`
    window.dispatchEvent(new CustomEvent("stay-view:preserve", { detail: { focusId: returnFocusId } }))
    window.dispatchEvent(new CustomEvent("offcanvas:load", {
      detail: { url: url.toString(), variant: "compact-right", returnFocusId, drawerId: this.drawerIdValue }
    }))
    this.announce("Booking proposal ready for confirmation.")
  }

  activeBaseUrl(segment) {
    return this.lastMode === "move" ? segment.dataset.moveUrl : segment.dataset.datesUrl
  }

  installPointerListeners() {
    this.pointerLifecycle = new AbortController()
    const options = { signal: this.pointerLifecycle.signal }
    window.addEventListener("pointermove", (event) => this.move(event), { ...options, passive: false })
    window.addEventListener("pointerup", (event) => this.finish(event), options)
    window.addEventListener("pointercancel", () => this.cancel(), options)
    window.addEventListener("keydown", (event) => this.cancel(event), options)
  }

  cancelPending() {
    window.clearTimeout(this.longPressTimer)
    this.pointerLifecycle?.abort()
    this.pointerLifecycle = null
    this.pending = null
  }

  cleanupInteraction() {
    if (this.active) {
      this.lastMode = this.active.mode
      try { this.active.segment.releasePointerCapture(this.active.pointerId) } catch (_) { /* No active capture. */ }
      delete this.active.segment.dataset.interacting
    }
    window.clearTimeout(this.longPressTimer)
    this.pointerLifecycle?.abort()
    this.pointerLifecycle = null
    this.stopAutoScroll()
    this.ghost?.remove()
    this.ghost = null
    this.rowTargets.forEach((row) => delete row.dataset.dropTarget)
    delete this.element.dataset.interactionState
    this.active = null
    this.pending = null
  }

  captureClick(event) {
    if (!this.suppressNextClick) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.suppressNextClick = false
    window.clearTimeout(this.suppressClickTimer)
  }

  preventTouchMenu(event) {
    if ((this.pending || this.active)?.pointerType === "touch") event.preventDefault()
  }

  startAutoScroll() {
    const tick = () => {
      if (!this.active) return
      const rect = this.element.getBoundingClientRect()
      const x = edgeVelocity(this.active.lastX, rect.left, rect.right)
      const y = edgeVelocity(this.active.lastY, rect.top, rect.bottom)
      if (x || y) {
        const beforeLeft = this.element.scrollLeft
        const beforeTop = this.element.scrollTop
        this.element.scrollBy(x, y)
        if (beforeLeft !== this.element.scrollLeft || beforeTop !== this.element.scrollTop) {
          this.updateProposal(this.active.lastX, this.active.lastY)
        }
      }
      this.autoScrollFrame = window.requestAnimationFrame(tick)
    }
    this.autoScrollFrame = window.requestAnimationFrame(tick)
  }

  stopAutoScroll() {
    if (this.autoScrollFrame) window.cancelAnimationFrame(this.autoScrollFrame)
    this.autoScrollFrame = null
  }

  createLiveRegion() {
    this.liveRegion = document.createElement("span")
    this.liveRegion.className = "sr-only"
    this.liveRegion.setAttribute("aria-live", "polite")
    this.liveRegion.setAttribute("data-stay-view--interaction-target", "live")
    this.element.append(this.liveRegion)
  }

  announce(message) {
    if (this.liveRegion) this.liveRegion.textContent = message
  }

  get dayCount() {
    return Number(this.element.dataset.trackCount) / 2
  }

  get dayWidth() {
    return this.cellTargets[0]?.getBoundingClientRect().width || 0
  }
}

function parseDate(value) {
  const [year, month, day] = value.split("-").map(Number)
  return Date.UTC(year, month - 1, day)
}

function formatDate(value) {
  return new Date(value).toISOString().slice(0, 10)
}

function shiftDate(value, days) {
  return formatDate(parseDate(value) + (days * DAY_MS))
}

function daysBetween(from, to) {
  return Math.round((parseDate(to) - parseDate(from)) / DAY_MS)
}

function edgeVelocity(position, start, finish) {
  const edge = 48
  const maximum = 12
  if (position < start + edge) return -Math.ceil(maximum * (1 - Math.max(0, position - start) / edge))
  if (position > finish - edge) return Math.ceil(maximum * (1 - Math.max(0, finish - position) / edge))
  return 0
}
