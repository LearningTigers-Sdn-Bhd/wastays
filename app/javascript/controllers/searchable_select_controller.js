import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hiddenInput", "options", "option", "placeholder"]

  connect() {
    this.close()
  }

  toggle() {
    if (this.optionsTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.optionsTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.filter()
    
    // Position dropdown to ensure it's visible
    this.positionDropdown()
    
    document.addEventListener("click", this.handleOutsideClick.bind(this))
  }

  close() {
    this.optionsTarget.classList.add("hidden")
    document.removeEventListener("click", this.handleOutsideClick.bind(this))
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase()
    let visibleCount = 0

    this.optionTargets.forEach(option => {
      const text = option.textContent.toLowerCase()
      const value = option.dataset.value.toLowerCase()
      
      if (text.includes(query) || value.includes(query)) {
        option.classList.remove("hidden")
        visibleCount++
      } else {
        option.classList.add("hidden")
      }
    })

    if (this.hasPlaceholderTarget) {
      if (visibleCount === 0) {
        this.placeholderTarget.classList.remove("hidden")
      } else {
        this.placeholderTarget.classList.add("hidden")
      }
    }
  }

  select(event) {
    const value = event.currentTarget.dataset.value
    const label = event.currentTarget.dataset.label

    this.hiddenInputTarget.value = value
    this.inputTarget.value = label
    
    // Trigger input event on hidden input for other controllers (like exchange-rate-calculator)
    this.hiddenInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    this.close()
  }

  positionDropdown() {
    const rect = this.element.getBoundingClientRect()
    const spaceBelow = window.innerHeight - rect.bottom
    const dropdownHeight = 300 // Max height set in CSS/Tailwind

    if (spaceBelow < dropdownHeight && rect.top > dropdownHeight) {
      this.optionsTarget.classList.add("bottom-full", "mb-2")
      this.optionsTarget.classList.remove("top-full", "mt-2")
    } else {
      this.optionsTarget.classList.add("top-full", "mt-2")
      this.optionsTarget.classList.remove("bottom-full", "mb-2")
    }
  }
}
