import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Navigates the tablet when the desk replaces the command region.
//
// The work happens in connect() rather than in response to an event: a Turbo
// Stream replace disconnects the old element and connects the new one, so
// arriving at all is the signal. That also makes a repeat push work, where a
// value change would not fire if the path happened to be identical.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.hasUrlValue || this.urlValue === "") return

    // Let the stream finish applying before leaving the page: navigating from
    // inside connect() can land mid-render on slower tablets.
    requestAnimationFrame(() => Turbo.visit(this.urlValue, { action: "replace" }))
  }
}
