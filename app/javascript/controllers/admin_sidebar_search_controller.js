import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "section", "item", "empty"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let visibleItems = 0

    this.sectionTargets.forEach((section) => {
      let sectionVisibleItems = 0

      section.querySelectorAll("[data-admin-sidebar-search-target='item']").forEach((item) => {
        const searchText = (item.dataset.searchText || item.textContent).trim().toLowerCase()
        const matches = query === "" || searchText.includes(query)

        item.classList.toggle("hidden", !matches)
        if (matches) sectionVisibleItems += 1
      })

      section.classList.toggle("hidden", sectionVisibleItems === 0)
      visibleItems += sectionVisibleItems
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visibleItems > 0)
    }
  }
}
