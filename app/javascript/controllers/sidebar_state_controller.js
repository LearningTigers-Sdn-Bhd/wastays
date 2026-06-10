import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { key: String }

  connect() {
    this.beforeVisitHandler = this.persistScroll.bind(this)
    this.loadHandler = this.syncAndRestore.bind(this)

    document.addEventListener("turbo:before-visit", this.beforeVisitHandler)
    document.addEventListener("turbo:load", this.loadHandler)

    this.syncAndRestore()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.beforeVisitHandler)
    document.removeEventListener("turbo:load", this.loadHandler)
  }

  syncAndRestore() {
    this.syncActiveLinks()
    this.restoreScroll()
  }

  syncActiveLinks() {
    const currentPath = this.normalize(window.location.pathname)
    const links = this.element.querySelectorAll("a.sidebar-nav-link[href]")

    links.forEach((link) => {
      const linkPath = this.linkPath(link)
      if (!linkPath) return

      const active = currentPath === linkPath
      this.toggleActive(link, active)
    })

    this.element.querySelectorAll("details.group").forEach((details) => {
      const summary = details.querySelector("summary.sidebar-nav-link")
      const hasActiveChild = Boolean(details.querySelector("a.sidebar-nav-link-active"))

      if (summary) this.toggleActive(summary, hasActiveChild)
      if (hasActiveChild) details.setAttribute("open", "open")
    })
  }

  persistScroll() {
    const desktop = this.scrollable(this.element)
    const mobile = this.scrollable(document.getElementById(`${this.keyValue}-sidebar-mobile`))

    if (desktop) sessionStorage.setItem(this.desktopScrollKey, String(desktop.scrollTop || 0))
    if (mobile) sessionStorage.setItem(this.mobileScrollKey, String(mobile.scrollTop || 0))
  }

  restoreScroll() {
    const desktop = this.scrollable(this.element)
    const mobile = this.scrollable(document.getElementById(`${this.keyValue}-sidebar-mobile`))

    this.restoreElementScroll(desktop, this.desktopScrollKey)
    this.restoreElementScroll(mobile, this.mobileScrollKey)
  }

  restoreElementScroll(element, key) {
    if (!element) return

    const saved = Number(sessionStorage.getItem(key) || 0)
    element.scrollTop = Number.isFinite(saved) ? saved : 0
  }

  toggleActive(element, active) {
    element.classList.toggle("sidebar-nav-link-active", active)
    element.classList.toggle("sidebar-nav-link-default", !active)
  }

  linkPath(link) {
    try {
      return this.normalize(new URL(link.href, window.location.origin).pathname)
    } catch (_) {
      return null
    }
  }

  scrollable(sidebar) {
    return sidebar?.querySelector(".flex-1.overflow-y-auto") || sidebar
  }

  normalize(path) {
    if (!path) return "/"
    return path.endsWith("/") && path.length > 1 ? path.slice(0, -1) : path
  }

  get desktopScrollKey() {
    return `wastays:${this.keyValue}-sidebar-desktop-scroll-top`
  }

  get mobileScrollKey() {
    return `wastays:${this.keyValue}-sidebar-mobile-scroll-top`
  }
}
