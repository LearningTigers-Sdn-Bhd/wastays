import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--sidebar
//
// Sidebar-wide state only. Collapsible, Tooltip, and Popover own their interaction,
// accessibility, dismissal, and Floating UI positioning contracts.
export default class extends Controller {
  static values = {
    key: String,
    surface: { type: String, default: "desktop" }
  }

  connect() {
    this.onTurboLoad = () => { this.syncActiveLinks(); this.restoreScroll() }
    this.onBeforeVisit = () => this.persistScroll()
    document.addEventListener("turbo:load", this.onTurboLoad)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)

    this.sheet = this.element.closest("dialog[data-controller~='panels-ui--sheet']")
    this.onSheetOpen = () => this.restoreScroll()
    this.sheet?.addEventListener("panels-ui:sheet-open", this.onSheetOpen)

    this.syncActiveLinks()
    this.restoreScroll()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.onTurboLoad)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    this.sheet?.removeEventListener("panels-ui:sheet-open", this.onSheetOpen)
  }

  get collapsed() {
    return this.surfaceValue === "desktop" && this.element.dataset.collapsed === "true"
  }

  get scrollable() {
    return this.element.querySelector(".panel-sidebar__body")
  }

  // Mark every rendered presentation of the longest route match. Desktop keeps
  // expanded and collapsed copies in the DOM, so selecting a single anchor would
  // leave one presentation stale after a Turbo visit.
  syncActiveLinks() {
    const current = this.normalize(window.location.pathname)
    const links = Array.from(this.element.querySelectorAll("a[data-sidebar-route][href]"))
    const activePath = links
      .map((link) => this.pathOf(link))
      .filter((path) => this.pathMatches(current, path))
      .sort((a, b) => b.length - a.length)[0]

    links.forEach((link) => {
      if (activePath && this.pathOf(link) === activePath) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })

    this.element.querySelectorAll("[data-sidebar-group-item]").forEach((groupItem) => {
      const hasActiveChild = Boolean(groupItem.querySelector('a[aria-current="page"]'))
      groupItem.toggleAttribute("data-sidebar-active", hasActiveChild)
      if (hasActiveChild && !this.collapsed) this.openCollapsible(groupItem)
    })
  }

  openCollapsible(groupItem) {
    const root = groupItem.querySelector(
      '[data-sidebar-presentation="expanded"] [data-controller~="panels-ui--collapsible"]'
    )
    const controller = root && this.application.getControllerForElementAndIdentifier(
      root,
      "panels-ui--collapsible"
    )
    controller?.open()
  }

  persistScroll() {
    const el = this.scrollable
    if (el && this.visible) sessionStorage.setItem(this.scrollKey, String(el.scrollTop || 0))
  }

  restoreScroll() {
    const el = this.scrollable
    if (!el || !this.visible) return
    const saved = Number(sessionStorage.getItem(this.scrollKey) || 0)
    el.scrollTop = Number.isFinite(saved) ? saved : 0
  }

  get scrollKey() {
    return `wastays:${this.keyValue}-sidebar-${this.surfaceValue}-scroll-top`
  }

  get visible() {
    return this.element.getClientRects().length > 0
  }

  pathMatches(current, path) {
    return Boolean(path) && (current === path || current.startsWith(`${path}/`))
  }

  pathOf(link) {
    try {
      if (link.getAttribute("href")?.startsWith("#")) return ""
      return this.normalize(new URL(link.href, window.location.origin).pathname)
    } catch (_) {
      return ""
    }
  }

  normalize(path) {
    if (!path) return "/"
    return path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
  }
}
