import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { stateKey: String }

  connect() {
    this.lifecycle = new AbortController()
    const request = this.focusRequests.get(this.storageKey) || this.storedFocusRequest
    this.pendingFocusId = request?.focusId || null
    this.pendingFallbackFocusId = request?.fallbackFocusId || null
    window.addEventListener("stay-view:preserve", (event) => this.preserve(event), { signal: this.lifecycle.signal })
    document.addEventListener("close", (event) => this.sheetClosed(event), { capture: true, signal: this.lifecycle.signal })
    document.addEventListener("turbo:before-stream-render", (event) => this.beforeStreamRender(event), { signal: this.lifecycle.signal })
    this.element.addEventListener("click", (event) => this.preserveBookingAction(event), { signal: this.lifecycle.signal })

    const restored = this.restoreSnapshot()
    if (!restored) {
      window.requestAnimationFrame(() => {
        this.centerToday()
        this.element.dataset.viewportSettled = "true"
      })
    }
  }

  disconnect() {
    this.saveSnapshot()
    this.lifecycle?.abort()
    if (this.restoreFrame) window.cancelAnimationFrame(this.restoreFrame)
  }

  preserve(event) {
    this.pendingFocusId = event.detail?.focusId || this.pendingFocusId
    this.pendingFallbackFocusId = event.detail?.fallbackFocusId || this.pendingFallbackFocusId
    if (this.pendingFocusId) {
      const request = { focusId: this.pendingFocusId, fallbackFocusId: this.pendingFallbackFocusId }
      this.focusRequests.set(this.storageKey, request)
      try { sessionStorage.setItem(this.focusStorageKey, JSON.stringify(request)) } catch (_) { /* Storage may be unavailable. */ }
    }
    this.saveSnapshot()
  }

  preserveBookingAction(event) {
    const trigger = event.target.closest("a[data-turbo-frame^='booking_action_sheet']")
    if (!trigger || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const owner = trigger.closest("[data-controller~='panels-ui--dropdown-menu'], [data-controller~='panels-ui--popover']")
    const ownerTrigger = owner?.querySelector(
      "[data-panels-ui--dropdown-menu-target='trigger'], [data-panels-ui--popover-target='trigger']"
    )
    // Match the room container by its explicit marker, not an id prefix: the
    // room's popovers/menus carry ids like "#{dom_id}-housekeeping" that also
    // start with "stay_view_room_", so a prefix match would stop at the popover
    // and miss the card's stable focus anchor (its -title / -status-trigger).
    const room = trigger.closest("[data-stay-view-room]")
    const fallback = room?.querySelector("[id$='-title'], [id$='-status-trigger']")
    const focusTarget = ownerTrigger || trigger
    const focusId = trigger.dataset.stayViewReturnFocusId || focusTarget.id || fallback?.id
    const fallbackFocusId = trigger.dataset.stayViewFallbackFocusId || fallback?.id
    if (!focusId) return

    if (ownerTrigger) ownerTrigger.focus({ preventScroll: true })
    this.preserve({ detail: { focusId, fallbackFocusId } })
  }

  // The booking-action Sheet lives in the shell layout, outside this element, so
  // its native `close` event is caught on `document` in the capture phase — that
  // runs before panels-ui--sheet-frame clears the frame, while the dialog (and
  // its navigation-pending flag) is still in the DOM. A pending navigation means
  // complete_sheet is about to move the page, so focus must not be restored here.
  sheetClosed(event) {
    const dialog = event.target
    if (!(dialog instanceof HTMLDialogElement)) return
    if (!dialog.closest("turbo-frame#booking_action_sheet")) return
    if (dialog.dataset.panelsNavigationPending === "true") return

    this.scheduleRestore()
  }

  beforeStreamRender(event) {
    const target = event.target.getAttribute("target")
    if (!target || !this.affectsViewport(target)) return

    this.saveSnapshot()
    const render = event.detail.render
    event.detail.render = (streamElement) => {
      render(streamElement)
      this.scheduleRestore()
    }
  }

  affectsViewport(target) {
    return target === "stay_view_board" || target === "stay_view_toolbar" || Boolean(this.element.querySelector(`#${CSS.escape(target)}`))
  }

  saveSnapshot() {
    const snapshot = {
      left: this.element.scrollLeft,
      top: this.element.scrollTop
    }
    try { sessionStorage.setItem(this.storageKey, JSON.stringify(snapshot)) } catch (_) { /* Storage may be unavailable. */ }
  }

  restoreSnapshot() {
    let snapshot
    try { snapshot = JSON.parse(sessionStorage.getItem(this.storageKey)) } catch (_) { return false }
    if (!snapshot) return false

    window.requestAnimationFrame(() => {
      this.element.scrollLeft = snapshot.left || 0
      this.element.scrollTop = snapshot.top || 0
      this.restoreFocus()
      this.element.dataset.viewportSettled = "true"
    })
    return true
  }

  scheduleRestore() {
    if (this.restoreFrame) window.cancelAnimationFrame(this.restoreFrame)
    this.restoreFrame = window.requestAnimationFrame(() => {
      this.restoreFrame = window.requestAnimationFrame(() => {
        this.restoreFrame = null
        this.restoreSnapshot()
      })
    })
  }

  restoreFocus() {
    if (!this.pendingFocusId) return
    if (document.querySelector("dialog[open]")) return

    const target = document.getElementById(this.pendingFocusId) || document.getElementById(this.pendingFallbackFocusId)
    if (!target) return

    const left = this.element.scrollLeft
    const top = this.element.scrollTop
    target.focus({ preventScroll: true })
    this.element.scrollLeft = left
    this.element.scrollTop = top
    if (document.activeElement !== target) return

    this.focusRequests.delete(this.storageKey)
    try { sessionStorage.removeItem(this.focusStorageKey) } catch (_) { /* Storage may be unavailable. */ }
    this.pendingFocusId = null
    this.pendingFallbackFocusId = null
  }

  centerToday() {
    const current = this.element.querySelector(".panel-timeline__date[data-current='true']")
    const roomHeader = this.element.querySelector(".panel-timeline__room-header")
    if (!current || !roomHeader) return

    const rootRect = this.element.getBoundingClientRect()
    const dateRect = current.getBoundingClientRect()
    const roomWidth = roomHeader.getBoundingClientRect().width
    const desiredCenter = rootRect.left + roomWidth + ((rootRect.width - roomWidth) / 2)
    this.element.scrollLeft += dateRect.left + (dateRect.width / 2) - desiredCenter
  }

  get storageKey() {
    return `stay-view:${this.stateKeyValue || "timeline"}`
  }

  get focusStorageKey() {
    return `${this.storageKey}:focus`
  }

  get storedFocusRequest() {
    try {
      const value = sessionStorage.getItem(this.focusStorageKey)
      if (!value) return null
      try { return JSON.parse(value) } catch (_) { return { focusId: value } }
    } catch (_) {
      return null
    }
  }

  get focusRequests() {
    window.__stayViewFocusRequests ||= new Map()
    return window.__stayViewFocusRequests
  }
}
