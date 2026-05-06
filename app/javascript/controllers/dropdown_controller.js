import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.toggleButton = this.element.querySelector("button")
    this.boundHandleOutsideClick = this.handleOutsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleOutsideClick)
  }

  // Toggles the dropdown menu
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const isHidden = this.menuTarget.classList.contains("hidden")

    // Close all other dropdowns on the page first
    document.querySelectorAll('[data-dropdown-target="menu"]').forEach(el => {
      el.classList.add("hidden")
    })

    if (isHidden) {
      if (this.isFloatingDropdown()) {
        this.positionFloatingMenu()
      }

      this.menuTarget.classList.remove("hidden")
      document.addEventListener("click", this.boundHandleOutsideClick)
    } else {
      this.menuTarget.classList.add("hidden")
      this.resetFloatingMenu()
      document.removeEventListener("click", this.boundHandleOutsideClick)
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
      this.resetFloatingMenu()
      document.removeEventListener("click", this.boundHandleOutsideClick)
    }
  }

  isFloatingDropdown() {
    return this.element.dataset.dropdownFloating === "true"
  }

  positionFloatingMenu() {
    if (!this.toggleButton) return

    const rect = this.toggleButton.getBoundingClientRect()
    // Keep floating menus compact by default while still respecting trigger width.
    const menuWidth = Math.max(rect.width, 220)
    const viewportPadding = 16
    const spacing = 8
    
    // Estimate menu height (max-height is 18rem = 288px)
    // We use a safe estimate to decide flipping
    const estimatedMenuHeight = 288 
    const spaceBelow = window.innerHeight - rect.bottom
    const spaceAbove = rect.top
    
    let top
    let isFlipped = false

    // If not enough space below AND more space above, flip it
    if (spaceBelow < (estimatedMenuHeight + spacing) && spaceAbove > spaceBelow) {
      top = rect.top - estimatedMenuHeight - spacing
      isFlipped = true
    } else {
      top = rect.bottom + spacing
    }

    const maxLeft = window.innerWidth - menuWidth - viewportPadding
    // Align menu's right edge with trigger's right edge, then clamp to viewport.
    const preferredLeft = rect.right - menuWidth
    const left = Math.min(Math.max(viewportPadding, preferredLeft), maxLeft)

    this.menuTarget.style.position = "fixed"
    this.menuTarget.style.left = `${left}px`
    this.menuTarget.style.right = "auto"
    this.menuTarget.style.top = `${top}px`
    this.menuTarget.style.minWidth = `${menuWidth}px`
    this.menuTarget.style.maxHeight = "18rem"
    this.menuTarget.style.zIndex = "9999"

    // Optional: add a class for styling adjustments if needed
    this.menuTarget.classList.toggle("dropdown-flipped", isFlipped)
  }

  resetFloatingMenu() {
    if (!this.isFloatingDropdown()) return

    this.menuTarget.style.position = ""
    this.menuTarget.style.left = ""
    this.menuTarget.style.right = ""
    this.menuTarget.style.top = ""
    this.menuTarget.style.minWidth = ""
    this.menuTarget.style.maxHeight = ""
    this.menuTarget.style.zIndex = ""
  }
}
