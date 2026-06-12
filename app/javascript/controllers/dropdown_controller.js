import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.toggleButton = this.hasButtonTarget ? this.buttonTarget : this.element.querySelector("button")
    this.menuElement = this.menuTarget
    this.boundHandleOutsideClick = this.handleOutsideClick.bind(this)
    this.boundPositionFloatingMenu = this.positionFloatingMenu.bind(this)
    this.boundHandleMenuKeydown = this.handleMenuKeydown.bind(this)
    this.boundClose = this.close.bind(this)
    this.menuPlaceholder = null

    window.addEventListener("dropdown:close-all", this.boundClose)
    window.addEventListener("offcanvas:open", this.boundClose)
  }

  disconnect() {
    this.restoreFloatingMenu()
    this.menuElement?.removeEventListener("keydown", this.boundHandleMenuKeydown)
    window.removeEventListener("dropdown:close-all", this.boundClose)
    window.removeEventListener("offcanvas:open", this.boundClose)
    this.stopTracking()
  }

  // Toggles the dropdown menu
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const isHidden = this.menuElement.classList.contains("hidden")

    // Close all other dropdowns on the page first
    document.querySelectorAll('[data-dropdown-target="menu"]').forEach(el => {
      if (el !== this.menuElement) el.classList.add("hidden")
    })

    if (isHidden) {
      this.menuElement.classList.remove("hidden")
      this.toggleButton?.setAttribute("aria-expanded", "true")
      
      if (this.isFloatingDropdown()) {
        this.portalFloatingMenu()
        this.positionFloatingMenu()
        this.startTracking()
      }

      document.addEventListener("click", this.boundHandleOutsideClick)
    } else {
      this.close()
    }
  }

  close() {
    this.menuElement.classList.add("hidden")
    this.toggleButton?.setAttribute("aria-expanded", "false")
    this.resetFloatingMenu()
    this.restoreFloatingMenu()
    this.stopTracking()
    document.removeEventListener("click", this.boundHandleOutsideClick)
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target) && !this.menuElement.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.menuElement.classList.contains("hidden")) this.toggle(event)
      this.menuItems[0]?.focus()
    }
  }

  handleMenuKeydown(event) {
    const currentIndex = this.menuItems.indexOf(document.activeElement)

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      this.toggleButton?.focus()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.menuItems[(currentIndex + 1) % this.menuItems.length]?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.menuItems[(currentIndex - 1 + this.menuItems.length) % this.menuItems.length]?.focus()
    }
  }

  get menuItems() {
    return Array.from(this.menuElement.querySelectorAll('[role="menuitem"]'))
  }

  startTracking() {
    window.addEventListener("scroll", this.boundPositionFloatingMenu, true)
    window.addEventListener("resize", this.boundPositionFloatingMenu)
    // Also track scroll on the immediate parent in case it's a scrollable container (like the currency tab bar)
    if (this.element.parentElement) {
      this.element.parentElement.addEventListener("scroll", this.boundPositionFloatingMenu)
    }
  }

  stopTracking() {
    window.removeEventListener("scroll", this.boundPositionFloatingMenu, true)
    window.removeEventListener("resize", this.boundPositionFloatingMenu)
    if (this.element.parentElement) {
      this.element.parentElement.removeEventListener("scroll", this.boundPositionFloatingMenu)
    }
  }

  isFloatingDropdown() {
    return this.element.dataset.dropdownFloating === "true"
  }

  portalFloatingMenu() {
    if (this.menuPlaceholder || this.menuElement.parentElement === document.body) return

    this.menuPlaceholder = document.createComment("dropdown-menu-placeholder")
    this.menuElement.before(this.menuPlaceholder)
    document.body.appendChild(this.menuElement)
    this.menuElement.addEventListener("keydown", this.boundHandleMenuKeydown)
  }

  restoreFloatingMenu() {
    if (!this.menuPlaceholder) return

    this.menuElement.removeEventListener("keydown", this.boundHandleMenuKeydown)
    this.menuPlaceholder.replaceWith(this.menuElement)
    this.menuPlaceholder = null
  }

  positionFloatingMenu() {
    if (!this.toggleButton || this.menuElement.classList.contains("hidden")) return

    const rect = this.toggleButton.getBoundingClientRect()
    // Keep floating menus compact by default while still respecting trigger width.
    const menuWidth = Math.max(rect.width, 220)
    const viewportPadding = 16
    const spacing = 8
    
    // Deciding flipping based on available space
    const menuHeight = this.menuElement.offsetHeight || 288
    const spaceBelow = window.innerHeight - rect.bottom
    const spaceAbove = rect.top
    
    let top
    let isFlipped = false

    // If not enough space below AND more space above, flip it
    if (spaceBelow < (menuHeight + spacing) && spaceAbove > spaceBelow) {
      top = rect.top - menuHeight - spacing
      isFlipped = true
    } else {
      top = rect.bottom + spacing
    }

    const maxLeft = window.innerWidth - menuWidth - viewportPadding
    // Prefer opening to the right so menus in the first timeline column are
    // not covered by the sticky room-details column.
    const toggleCenter = rect.left + (rect.width / 2)
    const preferredLeft = this.element.dataset.dropdownAlign === "right"
      ? rect.left
      : toggleCenter - (menuWidth / 2)
    const left = Math.min(Math.max(viewportPadding, preferredLeft), maxLeft)

    this.menuElement.style.position = "fixed"
    this.menuElement.style.left = `${left}px`
    this.menuElement.style.right = "auto"
    this.menuElement.style.top = `${top}px`
    this.menuElement.style.minWidth = `${menuWidth}px`
    this.menuElement.style.maxHeight = "18rem"
    this.menuElement.style.zIndex = "9999"

    // Optional: add a class for styling adjustments if needed
    this.menuElement.classList.toggle("dropdown-flipped", isFlipped)
  }

  resetFloatingMenu() {
    if (!this.isFloatingDropdown()) return

    this.menuElement.style.position = ""
    this.menuElement.style.left = ""
    this.menuElement.style.right = ""
    this.menuElement.style.top = ""
    this.menuElement.style.minWidth = ""
    this.menuElement.style.maxHeight = ""
    this.menuElement.style.zIndex = ""
  }
}
