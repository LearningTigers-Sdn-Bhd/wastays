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
    this.onCollapsibleChange = (event) => this.persistGroupState(event)
    document.addEventListener("turbo:load", this.onTurboLoad)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    this.element.addEventListener("panels-ui--collapsible:change", this.onCollapsibleChange)

    this.sheet = this.element.closest("dialog[data-controller~='panels-ui--sheet']")
    this.onSheetOpen = () => this.restoreScroll()
    this.sheet?.addEventListener("panels-ui:sheet-open", this.onSheetOpen)

    this.syncActiveLinks()
    this.restoreScroll()
    queueMicrotask(() => this.syncActiveLinks())
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.onTurboLoad)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    this.element.removeEventListener("panels-ui--collapsible:change", this.onCollapsibleChange)
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
      .flatMap((link) => this.pathsOf(link))
      .filter((path) => this.pathMatches(current, path))
      .sort((a, b) => b.length - a.length)[0]

    links.forEach((link) => {
      if (activePath && this.pathsOf(link).includes(activePath)) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })

    this.element.querySelectorAll("[data-sidebar-group-item]").forEach((groupItem) => {
      const hasActiveChild = Boolean(groupItem.querySelector('a[aria-current="page"]'))
      groupItem.toggleAttribute("data-sidebar-active", hasActiveChild)
      if (!this.collapsed) this.reconcileCollapsible(groupItem, hasActiveChild)
    })
  }

  reconcileCollapsible(groupItem, hasActiveChild) {
    const root = this.collapsibleRoot(groupItem)
    const controller = root && this.application.getControllerForElementAndIdentifier(
      root,
      "panels-ui--collapsible"
    )
    if (!controller) return

    const stored = this.groupStates[root.id]
    this.suppressGroupPersistence = true
    if (stored === true || (stored === undefined && hasActiveChild)) controller.open()
    else if (stored === false) controller.close()
    this.suppressGroupPersistence = false
  }

  persistGroupState(event) {
    if (this.suppressGroupPersistence) return

    const root = event.target.closest('[data-controller~="panels-ui--collapsible"]')
    if (!root?.id || !this.element.contains(root)) return

    const states = this.groupStates
    states[root.id] = Boolean(event.detail?.open)
    window.localStorage.setItem(this.groupStorageKey, JSON.stringify(states))
  }

  collapsibleRoot(groupItem) {
    if (this.surfaceValue === "desktop") {
      return groupItem.querySelector(
        '[data-sidebar-presentation="expanded"] [data-controller~="panels-ui--collapsible"]'
      )
    }
    return groupItem.querySelector('[data-controller~="panels-ui--collapsible"]')
  }

  get groupStorageKey() {
    return `wastays:${this.keyValue}-sidebar-${this.surfaceValue}-groups`
  }

  get groupStates() {
    try {
      return JSON.parse(window.localStorage.getItem(this.groupStorageKey) || "{}")
    } catch (_) {
      return {}
    }
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

  pathsOf(link) {
    const aliases = (link.dataset.sidebarActivePaths || "")
      .split(/\s+/)
      .filter(Boolean)
      .map((path) => this.normalize(new URL(path, window.location.origin).pathname))

    return [this.pathOf(link), ...aliases].filter(Boolean)
  }

  normalize(path) {
    if (!path) return "/"
    return path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path
  }
}
