import { Controller } from "@hotwired/stimulus"

// Filters the vendor list (both the List and Card panels at once, and either
// stays correctly filtered when concierge-view-mode switches which of them
// is visible -- each item's own hidden state persists independently of its
// panel's) by dietary label. "All" clears the filter entirely.
export default class extends Controller {
  static targets = ["button", "item", "empty"]

  filter(event) {
    const value = event.currentTarget.dataset.value

    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.value === value)
    })

    let visible = 0
    this.itemTargets.forEach((item) => {
      const matches = value === "" || item.dataset.dietary === value
      item.hidden = !matches
      if (matches) visible += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible > 0
  }
}
