import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "pillsContainer", "template", "option", "chevron"]
  static values = {
    selected: Array,
    all: Array
  }

  connect() {
    this.highlightedIndex = -1
    this.renderPills()
    this.filterOptions()
  }

  focusInput() {
    this.inputTarget.focus()
  }

  openDropdown() {
    this.dropdownTarget.classList.remove('hidden')
    this.chevronTarget.classList.add('rotate-180')
    this.filterOptions()
  }

  closeDropdown() {
    this.dropdownTarget.classList.add('hidden')
    this.chevronTarget.classList.remove('rotate-180')
    this.highlightedIndex = -1
    this.clearHighlight()
  }

  hideDropdown(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }

  stopProp(event) {
    event.stopPropagation()
  }

  filterOptions() {
    const query = this.inputTarget.value.toLowerCase()
    let visibleCount = 0

    this.optionTargets.forEach(option => {
      const name = option.dataset.name.toLowerCase()
      const id = option.dataset.id
      const isSelected = this.selectedValue.includes(id)
      const matches = name.includes(query)

      if (matches && !isSelected) {
        option.classList.remove('hidden')
        visibleCount++
      } else {
        option.classList.add('hidden')
      }
    })

    this.highlightedIndex = -1
    this.clearHighlight()

    if (visibleCount === 0 || (query === "" && !this.inputTarget.matches(':focus'))) {
      this.closeDropdown()
    } else {
      this.dropdownTarget.classList.remove('hidden')
      this.chevronTarget.classList.add('rotate-180')
    }
  }

  navigate(event) {
    const visibleOptions = this.optionTargets.filter(opt => !opt.classList.contains('hidden'))
    if (visibleOptions.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.highlightedIndex = (this.highlightedIndex + 1) % visibleOptions.length
        this.updateHighlight(visibleOptions)
        break
      case "ArrowUp":
        event.preventDefault()
        this.highlightedIndex = (this.highlightedIndex - 1 + visibleOptions.length) % visibleOptions.length
        this.updateHighlight(visibleOptions)
        break
      case "Enter":
        event.preventDefault()
        if (this.highlightedIndex >= 0) {
          visibleOptions[this.highlightedIndex].click()
        }
        break
      case "Escape":
        this.closeDropdown()
        break
    }
  }

  updateHighlight(visibleOptions) {
    this.clearHighlight()
    const highlightedOption = visibleOptions[this.highlightedIndex]
    if (highlightedOption) {
      highlightedOption.classList.add('bg-slate-100', 'text-slate-900')
      highlightedOption.scrollIntoView({ block: 'nearest' })
    }
  }

  clearHighlight() {
    this.optionTargets.forEach(opt => {
      opt.classList.remove('bg-slate-100', 'text-slate-900')
    })
  }

  select(event) {
    event.stopPropagation()
    const id = event.currentTarget.dataset.id
    if (!this.selectedValue.includes(id)) {
      this.selectedValue = [...this.selectedValue, id]
      this.inputTarget.value = ""
      this.renderPills()
      this.filterOptions()
    }
    this.inputTarget.focus()
  }

  remove(event) {
    event.stopPropagation()
    const id = event.currentTarget.dataset.id
    this.selectedValue = this.selectedValue.filter(val => val !== id)
    this.renderPills()
    this.filterOptions()
  }

  renderPills() {
    this.pillsContainerTarget.innerHTML = ""
    this.selectedValue.forEach(id => {
      const amenity = this.allValue.find(a => a.id === id)
      if (amenity) {
        const pill = document.importNode(this.templateTarget.content, true)
        pill.querySelector('[data-name]').textContent = amenity.name
        pill.querySelector('[data-remove-id]').dataset.id = id
        pill.querySelector('input').value = id
        this.pillsContainerTarget.appendChild(pill)
      }
    })
  }
}
