import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--sidebar-toggle
//
// Lives on the desktop collapse trigger. Mobile navigation is a PanelsUI::Sheet and
// uses the native command/commandfor contract instead of sidebar-owned overlay state.
export default class extends Controller {
  static values = { key: String }

  connect() {
    this.onBeforeRender = () => this.collapseBeforeRender()
    document.addEventListener("turbo:before-render", this.onBeforeRender)

    const sidebar = this.desktop
    const collapsible = Boolean(sidebar) && sidebar.dataset.collapsible !== "false"
    this.element.hidden = !collapsible
    this.applyDesktopState(sidebar, collapsible)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.onBeforeRender)
  }

  get desktop() {
    return document.getElementById(`${this.keyValue}-sidebar`)
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
    sidebar.dispatchEvent(new CustomEvent("panels-ui-sidebar:state-change", { detail: { collapsed } }))
  }

  collapseBeforeRender() {
    const sidebar = this.desktop
    if (!sidebar || sidebar.dataset.collapsible === "false") return

    this.setCollapsed(sidebar, true)
  }

  applyDesktopState(sidebar, collapsed) {
    if (!sidebar) return

    sidebar.dataset.collapsed = String(collapsed)
    this.element.setAttribute("aria-label", collapsed ? "Expand navigation" : "Collapse navigation")
    this.element.setAttribute("aria-expanded", String(!collapsed))
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
