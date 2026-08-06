import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--sidebar-search
//
// Type-to-filter the nav. Hides items whose search text doesn't match, hides sections
// left with no visible items, and reveals the empty-state message when nothing matches.
export default class extends Controller {
  static targets = ["input", "section", "item", "empty"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let visibleTotal = 0

    this.sectionTargets.forEach((section) => {
      let sectionVisible = 0

      section.querySelectorAll('[data-panels-ui--sidebar-search-target="item"]').forEach((item) => {
        const text = (item.dataset.searchText || item.textContent).trim().toLowerCase()
        const matches = query === "" || text.includes(query)
        item.classList.toggle("hidden", !matches)
        if (matches) sectionVisible += 1
      })

      section.classList.toggle("hidden", sectionVisible === 0)
      visibleTotal += sectionVisible
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visibleTotal > 0)
  }
}
