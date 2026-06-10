import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "menu"]

  connect() {
    this.closeHandler = this.close.bind(this)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const menu = button.closest("[data-breadcrumb-dropdown-target=\"item\"]")
      ?.querySelector("[data-breadcrumb-dropdown-target=\"menu\"]")

    if (!menu) return

    const wasOpen = !menu.classList.contains("hidden")
    this.closeAll()
    if (wasOpen) return

    this.positionMenu(button, menu)
    menu.classList.remove("hidden")

    document.addEventListener("click", this.closeHandler, { once: true })
  }

  close(event) {
    this.closeAll()
  }

  closeAll() {
    this.menuTargets.forEach((m) => m.classList.add("hidden"))
  }

  positionMenu(button, menu) {
    const rect = button.getBoundingClientRect()
    const margin = 8
    const menuWidth = 224
    const left = Math.min(Math.max(rect.left, margin), window.innerWidth - menuWidth - margin)

    menu.style.left = `${left}px`
    menu.style.top = `${rect.bottom + 6}px`
  }
}
