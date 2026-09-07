import { Controller } from "@hotwired/stimulus"

// Filters the amenity list inside the Manage amenities sheet and keeps the
// selected count live. A category heading hides with its last visible row, so a
// filtered list never shows an empty group.
export default class extends Controller {
  static targets = ["search", "category", "row", "group", "checkbox", "empty", "count"]

  connect() {
    if (!this.hasSearchTarget) return

    this.filter()
    this.updateCount()
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    const category = this.categoryTarget.querySelector("select")?.value || ""
    let visibleCount = 0

    this.rowTargets.forEach((row) => {
      const matchesQuery = !query || row.dataset.amenitySelectionSearchValue.includes(query)
      const matchesCategory = !category || row.dataset.amenitySelectionCategoryValue === category
      const visible = matchesQuery && matchesCategory
      row.classList.toggle("hidden", !visible)
      if (visible) visibleCount += 1
    })

    this.groupTargets.forEach((group) => {
      const hasVisibleRow = group.querySelector("[data-amenity-selection-target='row']:not(.hidden)")
      group.classList.toggle("hidden", !hasVisibleRow)
    })

    this.emptyTarget.classList.toggle("hidden", visibleCount > 0)
  }

  updateCount() {
    if (!this.hasCountTarget) return

    const count = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    this.countTarget.textContent = `${count} ${count === 1 ? "amenity" : "amenities"} selected`
  }
}
