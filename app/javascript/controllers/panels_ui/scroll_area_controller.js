import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--scroll-area
//
// Custom-scrollbar overlay for server-rendered Rails markup (shadcn/Radix ScrollArea).
// Native scrolling is preserved; this controller hides the OS bar (via CSS) and paints a
// proportional, draggable, auto-hiding thumb per axis. Measurement reacts to content and
// element resize so it stays correct across Turbo Frame/Stream swaps.
const MIN_THUMB = 20

export default class extends Controller {
  static targets = ["root", "viewport", "scrollbar", "thumb"]
  static values = { hideDelay: { type: Number, default: 600 } }

  connect() {
    this.dragging = null
    this.suppressClick = false

    this.resizeObserver = new ResizeObserver(() => this.refreshMeasurements())
    this.resizeObserver.observe(this.viewportTarget)
    if (this.viewportTarget.firstElementChild) {
      this.resizeObserver.observe(this.viewportTarget.firstElementChild)
    }

    this.mutationObserver = new MutationObserver(() => this.refreshMeasurements())
    this.mutationObserver.observe(this.viewportTarget, { childList: true, subtree: true, characterData: true })

    this.refreshMeasurements()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.mutationObserver?.disconnect()
    this.stopDrag()
    window.clearTimeout(this.hideTimer)
  }

  // --- Measurement ---------------------------------------------------------

  refreshMeasurements() {
    this.scrollbarTargets.forEach((scrollbar) => this.measureAxis(scrollbar))
  }

  updateScrollbarPosition() {
    this.scrollbarTargets.forEach((scrollbar) => this.positionThumb(scrollbar))
  }

  measureAxis(scrollbar) {
    const axis = scrollbar.dataset.orientation
    const { contentSize, viewportSize } = this.metrics(axis)
    const hasOverflow = contentSize - viewportSize > 1

    scrollbar.dataset.visible = String(hasOverflow)
    if (axis === "vertical") this.rootTarget.dataset.hasOverflowY = String(hasOverflow)
    else this.rootTarget.dataset.hasOverflowX = String(hasOverflow)

    if (!hasOverflow) return
    this.positionThumb(scrollbar)
  }

  positionThumb(scrollbar) {
    const axis = scrollbar.dataset.orientation
    const thumb = this.thumbFor(scrollbar)
    if (!thumb) return

    const { contentSize, viewportSize, scrollPos } = this.metrics(axis)
    const trackSize = axis === "vertical" ? scrollbar.clientHeight : scrollbar.clientWidth
    const maxScroll = contentSize - viewportSize
    if (maxScroll <= 0 || trackSize <= 0) return

    const thumbSize = Math.max(MIN_THUMB, (viewportSize / contentSize) * trackSize)
    const maxTravel = trackSize - thumbSize
    const thumbPos = (scrollPos / maxScroll) * maxTravel

    if (axis === "vertical") {
      thumb.style.height = `${thumbSize}px`
      thumb.style.transform = `translateY(${thumbPos}px)`
      this.rootTarget.dataset.overflowYStart = String(scrollPos > 0)
      this.rootTarget.dataset.overflowYEnd = String(scrollPos < maxScroll - 1)
    } else {
      thumb.style.width = `${thumbSize}px`
      thumb.style.transform = `translateX(${thumbPos}px)`
      this.rootTarget.dataset.overflowXStart = String(scrollPos > 0)
      this.rootTarget.dataset.overflowXEnd = String(scrollPos < maxScroll - 1)
    }
  }

  // --- Events --------------------------------------------------------------

  onViewportScroll() {
    this.updateScrollbarPosition()
    this.flagScrolling()
  }

  onRootMouseEnter() {
    window.clearTimeout(this.hideTimer)
    this.rootTarget.dataset.hovering = ""
  }

  onRootMouseLeave() {
    delete this.rootTarget.dataset.hovering
    if (!this.dragging) this.scheduleHide()
  }

  onThumbMouseDown(event) {
    event.preventDefault()
    event.stopPropagation()

    const thumb = event.currentTarget
    const scrollbar = thumb.closest(".panel-scroll-area__scrollbar")
    const axis = thumb.dataset.orientation
    const { contentSize, viewportSize, scrollPos } = this.metrics(axis)
    const trackSize = axis === "vertical" ? scrollbar.clientHeight : scrollbar.clientWidth
    const thumbSize = axis === "vertical" ? thumb.offsetHeight : thumb.offsetWidth

    this.dragging = {
      axis,
      start: axis === "vertical" ? event.clientY : event.clientX,
      startScroll: scrollPos,
      ratio: (contentSize - viewportSize) / (trackSize - thumbSize)
    }

    this.rootTarget.dataset.scrolling = ""
    window.clearTimeout(this.hideTimer)
    document.addEventListener("mousemove", this.onDragMove)
    document.addEventListener("mouseup", this.onDragEnd)
  }

  onScrollbarClick(event) {
    if (this.suppressClick) return
    if (event.target.classList.contains("panel-scroll-area__thumb")) return

    const scrollbar = event.currentTarget
    const axis = scrollbar.dataset.orientation
    const thumb = this.thumbFor(scrollbar)
    if (!thumb) return

    const rect = scrollbar.getBoundingClientRect()
    const { contentSize, viewportSize } = this.metrics(axis)
    const trackSize = axis === "vertical" ? scrollbar.clientHeight : scrollbar.clientWidth
    const thumbSize = axis === "vertical" ? thumb.offsetHeight : thumb.offsetWidth
    const clickPos = axis === "vertical" ? event.clientY - rect.top : event.clientX - rect.left

    const maxScroll = contentSize - viewportSize
    const maxTravel = trackSize - thumbSize
    if (maxTravel <= 0) return

    const thumbPos = Math.max(0, Math.min(clickPos - thumbSize / 2, maxTravel))
    const target = (thumbPos / maxTravel) * maxScroll
    this.viewportTarget.scrollTo({ [axis === "vertical" ? "top" : "left"]: target, behavior: "smooth" })
  }

  // --- Drag handlers (bound) ----------------------------------------------

  onDragMove = (event) => {
    if (!this.dragging) return
    const { axis, start, startScroll, ratio } = this.dragging
    const delta = (axis === "vertical" ? event.clientY : event.clientX) - start
    const next = startScroll + delta * ratio

    if (axis === "vertical") this.viewportTarget.scrollTop = next
    else this.viewportTarget.scrollLeft = next
  }

  onDragEnd = () => {
    this.stopDrag()
    this.suppressClick = true
    window.setTimeout(() => { this.suppressClick = false }, 0)
    if (!("hovering" in this.rootTarget.dataset)) this.scheduleHide()
  }

  // --- Helpers -------------------------------------------------------------

  stopDrag() {
    this.dragging = null
    document.removeEventListener("mousemove", this.onDragMove)
    document.removeEventListener("mouseup", this.onDragEnd)
  }

  flagScrolling() {
    this.rootTarget.dataset.scrolling = ""
    window.clearTimeout(this.hideTimer)
    this.scheduleHide()
  }

  scheduleHide() {
    window.clearTimeout(this.hideTimer)
    this.hideTimer = window.setTimeout(() => {
      delete this.rootTarget.dataset.scrolling
    }, this.hideDelayValue)
  }

  metrics(axis) {
    const v = this.viewportTarget
    if (axis === "vertical") {
      return { contentSize: v.scrollHeight, viewportSize: v.clientHeight, scrollPos: v.scrollTop }
    }
    return { contentSize: v.scrollWidth, viewportSize: v.clientWidth, scrollPos: v.scrollLeft }
  }

  thumbFor(scrollbar) {
    return scrollbar.querySelector(".panel-scroll-area__thumb")
  }
}
