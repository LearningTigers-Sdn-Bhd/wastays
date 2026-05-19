import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollToTop()
  }

  scrollToTop() {
    // Find the nearest scrollable parent (the offcanvas drawer body)
    const scrollableContainer = this.element.closest('.overflow-y-auto')
    
    if (scrollableContainer) {
      scrollableContainer.scrollTo({
        top: 0,
        behavior: 'smooth'
      })
    } else {
      window.scrollTo({
        top: 0,
        behavior: 'smooth'
      })
    }
  }
}
