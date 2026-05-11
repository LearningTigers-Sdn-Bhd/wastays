import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["expandedContent", "collapsedContent", "showMoreButton"]

  connect() {
    this.expanded = false
  }

  toggle() {
    this.expanded = !this.expanded
    
    if (this.expanded) {
      this.expandedContentTarget.classList.remove("hidden")
      this.collapsedContentTarget.classList.add("hidden")
      this.showMoreButtonTarget.innerText = "Show less"
    } else {
      this.expandedContentTarget.classList.add("hidden")
      this.collapsedContentTarget.classList.remove("hidden")
      this.showMoreButtonTarget.innerText = "Show more"
    }
  }
}
