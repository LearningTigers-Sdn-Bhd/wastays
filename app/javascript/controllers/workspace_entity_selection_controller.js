import { Controller } from "@hotwired/stimulus"

let pendingFocus = null

export default class extends Controller {
  connect() {
    if (!pendingFocus || document.documentElement.hasAttribute("data-turbo-preview")) return

    const focus = pendingFocus
    pendingFocus = null
    if (focus.location !== this.locationKey(window.location.href)) return

    requestAnimationFrame(() => document.getElementById(focus.headingId)?.focus({ preventScroll: true }))
  }

  select(event) {
    pendingFocus = {
      headingId: event.params.heading,
      location: this.locationKey(event.currentTarget.href)
    }
  }

  locationKey(href) {
    const url = new URL(href, window.location.origin)
    return `${url.pathname}${url.search}`
  }
}
