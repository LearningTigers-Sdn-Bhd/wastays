import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "pillsContainer", "template", "checkbox", "option", "chevron", "placeholder"]
  static values = {
    selected: Array,
    all: Array
  }

  connect() {
    this.renderPills()
    this.updateCheckboxes()
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
    this.collapseAllCategories()
  }

  hideDropdown(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }

  stopProp(event) {
    event.stopPropagation()
  }

  collapseAllCategories() {
    const categories = this.element.querySelectorAll('[data-category-container]')
    categories.forEach(category => {
      const content = category.querySelector('[data-category-content]')
      const chevron = category.querySelector('[data-category-chevron]')
      if (content) content.classList.add('hidden')
      if (chevron) chevron.classList.remove('rotate-180')
    })
  }

  toggleCategory(event) {
    event.stopPropagation()
    const container = event.currentTarget.closest('[data-category-container]')
    const content = container.querySelector('[data-category-content]')
    const chevron = event.currentTarget.querySelector('[data-category-chevron]')
    
    content.classList.toggle('hidden')
    if (chevron) chevron.classList.toggle('rotate-180')
  }

  filterOptions() {
    const query = this.inputTarget.value.toLowerCase()
    let visibleCount = 0

    const categories = this.element.querySelectorAll('[data-category-container]')
    
    categories.forEach(category => {
      const categoryName = (category.dataset.categoryName || "").toLowerCase()
      const options = category.querySelectorAll('[data-multi-select-dropdown-target="option"]')
      let categoryHasVisibleOptions = false
      const categoryMatches = query.length > 0 && categoryName.includes(query)

      options.forEach(option => {
        const name = option.dataset.name.toLowerCase()
        const matches = name.includes(query) || categoryMatches

        if (matches) {
          option.classList.remove('hidden')
          categoryHasVisibleOptions = true
          visibleCount++
        } else {
          option.classList.add('hidden')
        }
      })

      const content = category.querySelector('[data-category-content]')
      const chevron = category.querySelector('[data-category-chevron]')

      if (categoryHasVisibleOptions) {
        category.classList.remove('hidden')
        if (query.length > 0) {
          if (content) content.classList.remove('hidden')
          if (chevron) chevron.classList.add('rotate-180')
        } else {
          if (content) content.classList.add('hidden')
          if (chevron) chevron.classList.remove('rotate-180')
        }
      } else {
        category.classList.add('hidden')
      }
    })

    if (this.hasPlaceholderTarget) {
      if (visibleCount === 0 && query !== "") {
        this.placeholderTarget.classList.remove('hidden')
      } else {
        this.placeholderTarget.classList.add('hidden')
      }
    }
  }

  toggle(event) {
    const id = event.target.dataset.id
    const isChecked = event.target.checked

    if (isChecked) {
      if (!this.selectedValue.includes(id)) {
        this.selectedValue = [...this.selectedValue, id]
      }
    } else {
      this.selectedValue = this.selectedValue.filter(val => val !== id)
    }

    this.renderPills()
    this.updateCheckboxes()
  }

  remove(event) {
    event.stopPropagation()
    const id = event.currentTarget.dataset.id
    this.selectedValue = this.selectedValue.filter(val => val !== id)
    this.renderPills()
    this.updateCheckboxes()
  }

  updateCheckboxes() {
    this.checkboxTargets.forEach(cb => {
      cb.checked = this.selectedValue.includes(cb.dataset.id)
      
      // Update visual state of the option row
      const option = cb.closest('[data-multi-select-dropdown-target="option"]')
      if (option) {
        if (cb.checked) {
          option.classList.add('bg-slate-50')
        } else {
          option.classList.remove('bg-slate-50')
        }
      }
    })
  }

  renderPills() {
    this.pillsContainerTarget.innerHTML = ""
    this.selectedValue.forEach(id => {
      const amenity = this.allValue.find(a => (a.id || a.slug) === id)
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
