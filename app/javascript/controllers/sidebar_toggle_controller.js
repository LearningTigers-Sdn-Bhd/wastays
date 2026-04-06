import { Controller } from "@hotwired/stimulus"

// Handles mobile sidebar toggle for the Preline CMS-style layout
export default class extends Controller {
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
}
