import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { stateKey: String }

  connect() {
    this.lifecycle = new AbortController()
    this.pendingFocusId = this.focusRequests.get(this.storageKey) || this.storedFocusId
    window.addEventListener("stay-view:preserve", (event) => this.preserve(event), { signal: this.lifecycle.signal })
    window.addEventListener("offcanvas:closed", () => this.scheduleRestore(), { signal: this.lifecycle.signal })
    window.addEventListener("panels-ui:sheet-closed", () => this.clearRestoredFocusRequest(), { signal: this.lifecycle.signal })
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
    if (this.pendingFocusId) {
      this.focusRequests.set(this.storageKey, this.pendingFocusId)
      try { sessionStorage.setItem(this.focusStorageKey, this.pendingFocusId) } catch (_) { /* Storage may be unavailable. */ }
    }
    this.saveSnapshot()
  }

  preserveBookingAction(event) {
    const trigger = event.target.closest("a[data-turbo-frame^='booking_action_sheet']")
    if (!trigger?.id || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    this.preserve({ detail: { focusId: trigger.id } })
  }

  clearRestoredFocusRequest() {
    window.requestAnimationFrame(() => {
      if (!this.pendingFocusId || document.activeElement?.id !== this.pendingFocusId) return

      this.focusRequests.delete(this.storageKey)
      try { sessionStorage.removeItem(this.focusStorageKey) } catch (_) { /* Storage may be unavailable. */ }
      this.pendingFocusId = null
    })
  }

  beforeStreamRender(event) {
    const target = event.target.getAttribute("target")
    if (!target || !this.affectsTimeline(target)) return

    this.saveSnapshot()
    const render = event.detail.render
    event.detail.render = (streamElement) => {
      render(streamElement)
      this.scheduleRestore()
    }
  }

  affectsTimeline(target) {
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
    const target = document.getElementById(this.pendingFocusId)
    if (!target) return

    const left = this.element.scrollLeft
    const top = this.element.scrollTop
    target.focus({ preventScroll: true })
    this.element.scrollLeft = left
    this.element.scrollTop = top
    this.focusRequests.delete(this.storageKey)
    try { sessionStorage.removeItem(this.focusStorageKey) } catch (_) { /* Storage may be unavailable. */ }
    this.pendingFocusId = null
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

  get storedFocusId() {
    try { return sessionStorage.getItem(this.focusStorageKey) } catch (_) { return null }
  }

  get focusRequests() {
    window.__stayViewFocusRequests ||= new Map()
    return window.__stayViewFocusRequests
  }
}
