import { Controller } from "@hotwired/stimulus"

// Shared with PanelsUI::Sidebar::GROUP_STATE_COOKIE (Ruby). We record each user
// toggle here; the server reads it to render every group's open/closed state on
// first paint. The client never re-opens or re-closes a group after load — the
// server render plus Turbo's permanent sidebar are the single source of truth.
const GROUP_STATE_COOKIE = "sidebar_groups"

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
    this.onBeforeVisit = (event) => this.beforeVisit(event)
    this.onBeforeRender = (event) => this.refreshForModeChange(event)
    this.onCollapsibleChange = (event) => this.persistGroupState(event)
    document.addEventListener("turbo:load", this.onTurboLoad)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    document.addEventListener("turbo:before-render", this.onBeforeRender)
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
    document.removeEventListener("turbo:before-render", this.onBeforeRender)
    this.element.removeEventListener("panels-ui--collapsible:change", this.onCollapsibleChange)
    this.sheet?.removeEventListener("panels-ui:sheet-open", this.onSheetOpen)
  }

  refreshForModeChange(event) {
    if (this.surfaceValue !== "desktop" || !this.element.id) return

    const nextSidebar = event.detail.newBody?.querySelector(`#${this.element.id}`)
    if (!nextSidebar || nextSidebar.dataset.sidebarMode === this.element.dataset.sidebarMode) return

    this.element.dataset.sidebarMode = nextSidebar.dataset.sidebarMode
    this.element.innerHTML = nextSidebar.innerHTML
    queueMicrotask(() => this.syncActiveLinks())
  }

  get scrollable() {
    return this.element.querySelector(".panel-sidebar__body")
  }

  beforeVisit(event) {
    this.persistScroll()

    // Desktop and mobile presentations are connected at the same time. Let one
    // controller own visit cancellation while both persist their own scroll state.
    if (this.surfaceValue !== "desktop" || !event.detail?.url) return

    try {
      const destination = new URL(event.detail.url, window.location.href)
      if (destination.href === window.location.href) event.preventDefault()
    } catch (_) {
      // Let Turbo handle malformed or otherwise unsupported destinations.
    }
  }

  // Mark every rendered presentation of the longest route match. Desktop keeps
  // expanded and collapsed copies in the DOM, so selecting a single anchor would
  // leave one presentation stale after a Turbo visit. Open/closed state is left
  // untouched — the server render and Turbo's permanent sidebar own it.
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
      groupItem.toggleAttribute("data-sidebar-active", Boolean(groupItem.querySelector('a[aria-current="page"]')))
    })
  }

  persistGroupState(event) {
    const root = event.target.closest('[data-controller~="panels-ui--collapsible"]')
    if (!root?.id || !this.element.contains(root)) return

    const states = this.groupStates
    states[root.id] = Boolean(event.detail?.open)
    this.writeGroupCookie(states)
  }

  // Flat `{ collapsibleId => bool }` map, shared across every sidebar surface and
  // portal in one cookie. Ids are fully qualified, so entries never collide.
  get groupStates() {
    try {
      return JSON.parse(this.readGroupCookie() || "{}")
    } catch (_) {
      return {}
    }
  }

  readGroupCookie() {
    const row = document.cookie
      .split("; ")
      .find((entry) => entry.startsWith(`${GROUP_STATE_COOKIE}=`))
    return row ? decodeURIComponent(row.slice(GROUP_STATE_COOKIE.length + 1)) : null
  }

  writeGroupCookie(states) {
    const value = encodeURIComponent(JSON.stringify(states))
    document.cookie = `${GROUP_STATE_COOKIE}=${value}; path=/; max-age=31536000; samesite=lax`
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
