import { Controller } from "@hotwired/stimulus"

// Module state survives Turbo page renders but resets on a full browser refresh.
const lockStates = new Map()

// Identifier: panels-ui--sidebar-toggle
//
// Lives on the desktop lock trigger. Mobile navigation is a PanelsUI::Sheet and
// uses the native command/commandfor contract instead of sidebar-owned overlay state.
export default class extends Controller {
  static values = { key: String, stateKey: String }

  connect() {
    this.onBeforeRender = () => this.collapseBeforeRender()
    this.onTurboLoad = () => this.initializeDesktop({ hideWhenMissing: true })
    document.addEventListener("turbo:before-render", this.onBeforeRender)
    document.addEventListener("turbo:load", this.onTurboLoad)
    this.initializeDesktop()
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.onBeforeRender)
    document.removeEventListener("turbo:load", this.onTurboLoad)
    this.unbindDesktop()
  }

  get desktop() {
    return document.getElementById(`${this.keyValue}-sidebar`)
  }

  initializeDesktop({ hideWhenMissing = false } = {}) {
    const sidebar = this.desktop
    if (!sidebar) {
      if (hideWhenMissing) this.element.hidden = true
      return
    }

    const collapsible = sidebar.dataset.collapsible !== "false"
    this.element.hidden = !collapsible
    this.bindDesktop(sidebar)

    if (!collapsible) {
      sidebar.dataset.locked = "false"
      this.applyDesktopState(sidebar, false)
      return
    }

    const locked = lockStates.get(this.lockKey) === true
    sidebar.dataset.locked = String(locked)
    this.applyDesktopState(sidebar, !locked)
  }

  bindDesktop(sidebar) {
    if (this.boundSidebar === sidebar) return
    this.unbindDesktop()

    this.boundSidebar = sidebar
    this.onPointerEnter = (event) => this.expandTemporarily(event)
    this.onPointerLeave = (event) => this.endTemporaryExpansion(event)
    this.onFocusOut = () => queueMicrotask(() => this.syncTemporaryExpansion())
    sidebar.addEventListener("pointerenter", this.onPointerEnter)
    sidebar.addEventListener("pointerleave", this.onPointerLeave)
    sidebar.addEventListener("focusout", this.onFocusOut)
  }

  unbindDesktop() {
    if (!this.boundSidebar) return

    this.boundSidebar.removeEventListener("pointerenter", this.onPointerEnter)
    this.boundSidebar.removeEventListener("pointerleave", this.onPointerLeave)
    this.boundSidebar.removeEventListener("focusout", this.onFocusOut)
    this.boundSidebar = null
    this.pointerInside = false
  }

  expandTemporarily(event) {
    if (event.pointerType && event.pointerType !== "mouse") return

    this.pointerInside = true
    if (!this.locked && !this.collapsedFocusWithin) this.setCollapsed(this.desktop, false)
  }

  endTemporaryExpansion(event) {
    if (event.pointerType && event.pointerType !== "mouse") return

    this.pointerInside = false
    this.syncTemporaryExpansion()
  }

  syncTemporaryExpansion() {
    if (this.locked) return

    if (this.pointerInside) {
      if (!this.collapsedFocusWithin) this.setCollapsed(this.desktop, false)
    } else if (!this.expandedFocusWithin) {
      this.setCollapsed(this.desktop, true)
    }
  }

  // ── Desktop lock ──
  toggleDesktop() {
    const sidebar = this.desktop
    if (!sidebar || sidebar.dataset.collapsible === "false") return

    const locked = !this.locked
    lockStates.set(this.lockKey, locked)
    sidebar.dataset.locked = String(locked)
    this.setCollapsed(sidebar, !(locked || this.pointerInside || this.expandedFocusWithin), { refresh: true })
  }

  setCollapsed(sidebar, collapsed, { refresh = false } = {}) {
    if (!sidebar || sidebar.dataset.collapsible === "false") return
    if (!refresh && sidebar.dataset.collapsed === String(collapsed)) return

    this.closeFloatingLayers()
    this.applyDesktopState(sidebar, collapsed)
    sidebar.dispatchEvent(new CustomEvent("panels-ui-sidebar:state-change", { detail: { collapsed } }))
  }

  collapseBeforeRender() {
    const sidebar = this.desktop
    if (!sidebar || sidebar.dataset.collapsible === "false") return

    this.pointerInside = false
    if (!this.locked) this.setCollapsed(sidebar, true)
  }

  applyDesktopState(sidebar, collapsed) {
    if (!sidebar) return

    sidebar.dataset.collapsed = String(collapsed)
    this.element.setAttribute("aria-label", this.locked ? "Unlock navigation" : "Lock navigation open")
    this.element.setAttribute("aria-expanded", String(!collapsed))
    this.element.setAttribute("aria-pressed", String(this.locked))
    this.element.querySelectorAll("[data-sidebar-toggle-icon]").forEach((icon) => {
      icon.toggleAttribute("hidden", icon.dataset.sidebarToggleIcon !== (this.locked ? "unlock" : "lock"))
    })
    sidebar.querySelectorAll("[data-sidebar-presentation]").forEach((presentation) => {
      const active = presentation.dataset.sidebarPresentation === (collapsed ? "collapsed" : "expanded")
      presentation.hidden = !active
      presentation.inert = !active
    })
  }

  closeFloatingLayers() {
    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: null } }))
  }

  get lockKey() {
    return this.hasStateKeyValue ? this.stateKeyValue : this.keyValue
  }

  get locked() {
    return this.desktop?.dataset.locked === "true"
  }

  get collapsedFocusWithin() {
    const presentation = document.activeElement?.closest?.("[data-sidebar-presentation='collapsed']")
    return Boolean(presentation && this.desktop?.contains(presentation))
  }

  get expandedFocusWithin() {
    const sidebar = this.desktop
    const activeElement = document.activeElement
    if (!sidebar || sidebar.dataset.collapsed !== "false" || !sidebar.contains(activeElement)) return false

    return !activeElement.closest?.("[data-sidebar-presentation='collapsed']")
  }
}
