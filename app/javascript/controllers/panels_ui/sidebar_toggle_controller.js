import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--sidebar-toggle
//
// Lives on the desktop collapse trigger. Mobile navigation is a PanelsUI::Sheet and
// uses the native command/commandfor contract instead of sidebar-owned overlay state.
export default class extends Controller {
  static values = { key: String, stateKey: String }

  connect() {
    this.applyStoredCollapse()
  }

  get desktop() {
    return document.getElementById(`${this.keyValue}-sidebar`)
  }

  get storageKey() {
    return `wastays:${this.stateKeyValue}-sidebar-collapsed`
  }

  // ── Desktop collapse ──
  toggleDesktop() {
    const sidebar = this.desktop
    if (sidebar?.dataset.collapsible !== "false") {
      this.setCollapsed(sidebar, sidebar.dataset.collapsed !== "true")
    }
  }

  setCollapsed(sidebar, collapsed) {
    if (sidebar.dataset.collapsible === "false") return

    this.closeFloatingLayers()
    this.applyDesktopState(sidebar, collapsed)
    window.localStorage.setItem(this.storageKey, collapsed ? "1" : "0")
    sidebar.dispatchEvent(new CustomEvent("panels-ui-sidebar:state-change", { detail: { collapsed } }))
  }

  applyStoredCollapse() {
    const sidebar = this.desktop
    if (!sidebar || sidebar.dataset.collapsible === "false") return
    this.applyDesktopState(sidebar, window.localStorage.getItem(this.storageKey) === "1")
  }

  applyDesktopState(sidebar, collapsed) {
    sidebar.dataset.collapsed = String(collapsed)
    sidebar.querySelectorAll("[data-sidebar-presentation]").forEach((presentation) => {
      const active = presentation.dataset.sidebarPresentation === (collapsed ? "collapsed" : "expanded")
      presentation.hidden = !active
      presentation.inert = !active
    })
  }

  closeFloatingLayers() {
    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: null } }))
  }
}
