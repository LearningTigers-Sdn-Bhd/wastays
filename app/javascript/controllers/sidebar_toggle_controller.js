import { Controller } from "@hotwired/stimulus"

// Handles mobile sidebar toggle for the Preline CMS-style layout
export default class extends Controller {
  connect() {
    this.applyStoredDesktopState()
  }

  toggle() {
    // Find the mobile sidebar and overlay based on which layout we're in
    const adminSidebar = document.getElementById("admin-sidebar-mobile")
    const adminOverlay = document.getElementById("admin-sidebar-overlay")
    const hotelSidebar = document.getElementById("hotel-sidebar-mobile")
    const hotelOverlay = document.getElementById("hotel-sidebar-overlay")

    const sidebar = adminSidebar || hotelSidebar
    const overlay = adminOverlay || hotelOverlay

    if (!sidebar) return

    const isOpen = !sidebar.classList.contains("-translate-x-full")

    if (isOpen) {
      this.closeSidebar(sidebar, overlay)
    } else {
      this.openSidebar(sidebar, overlay)
    }
  }

  close() {
    const adminSidebar = document.getElementById("admin-sidebar-mobile")
    const adminOverlay = document.getElementById("admin-sidebar-overlay")
    const hotelSidebar = document.getElementById("hotel-sidebar-mobile")
    const hotelOverlay = document.getElementById("hotel-sidebar-overlay")

    const sidebar = adminSidebar || hotelSidebar
    const overlay = adminOverlay || hotelOverlay

    if (sidebar) this.closeSidebar(sidebar, overlay)
  }

  openSidebar(sidebar, overlay) {
    sidebar.classList.remove("-translate-x-full")
    sidebar.classList.add("translate-x-0")
    if (overlay) overlay.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  closeSidebar(sidebar, overlay) {
    sidebar.classList.add("-translate-x-full")
    sidebar.classList.remove("translate-x-0")
    if (overlay) overlay.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  toggleDesktop() {
    const sidebar = this.desktopSidebar()
    if (!sidebar) return

    const collapsed = !this.isDesktopCollapsed(sidebar)
    this.applyDesktopState(sidebar, collapsed)
    this.persistDesktopState(collapsed)
  }

  applyStoredDesktopState() {
    const sidebar = this.desktopSidebar()
    if (!sidebar) return

    const stored = window.localStorage.getItem(this.storageKey())
    this.applyDesktopState(sidebar, stored === "1")
  }

  applyDesktopState(sidebar, collapsed) {
    sidebar.classList.toggle("w-[260px]", !collapsed)
    sidebar.classList.toggle("w-[84px]", collapsed)

    const labels = sidebar.querySelectorAll(".sidebar-section-label, a.sidebar-nav-link span")
    labels.forEach((node) => node.classList.toggle("hidden", collapsed))

    const links = sidebar.querySelectorAll("a.sidebar-nav-link")
    links.forEach((link) => {
      link.classList.toggle("justify-center", collapsed)
      const label = link.querySelector("span")?.textContent?.trim()
      if (collapsed && label) {
        link.setAttribute("title", label)
      } else {
        link.removeAttribute("title")
      }
    })

    const searchInput = sidebar.querySelector('input[type="search"]')
    const searchContainer = searchInput?.closest("div.p-4.pb-2")
    if (searchContainer) {
      searchContainer.classList.toggle("hidden", collapsed)
    }
  }

  isDesktopCollapsed(sidebar) {
    return sidebar.classList.contains("w-[84px]")
  }

  desktopSidebar() {
    return document.getElementById("admin-sidebar") || document.getElementById("hotel-sidebar")
  }

  storageKey() {
    return document.getElementById("admin-sidebar") ? "wastays:admin-sidebar-collapsed" : "wastays:hotel-sidebar-collapsed"
  }

  persistDesktopState(collapsed) {
    window.localStorage.setItem(this.storageKey(), collapsed ? "1" : "0")
  }
}
