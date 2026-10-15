import { Controller } from "@hotwired/stimulus"

// The concierge hero sticks as a slim bar once the guest scrolls past it. The
// sentinel covers the part of the hero that scrolls away, so it leaves the
// screen at the moment the bar pins. An observer, not a scroll listener: the
// iOS bounce at the top of the page never moves the sentinel out of view.
export default class extends Controller {
  static targets = ["sentinel"]

  connect() {
    this.observer = new IntersectionObserver(([entry]) => {
      this.element.toggleAttribute("data-compact", !entry.isIntersecting)
    })
    this.observer.observe(this.sentinelTarget)
  }

  disconnect() {
    this.observer.disconnect()
  }
}
