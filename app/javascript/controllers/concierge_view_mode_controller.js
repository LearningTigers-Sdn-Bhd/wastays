import { Controller } from "@hotwired/stimulus"

// Toggles between the List and Card renderings of the vendor listing. Both
// are rendered by the server up front; this only ever flips which panel is
// hidden, so switching is instant and needs no request.
export default class extends Controller {
  static targets = ["tab", "panel"]

  show(event) {
    const mode = event.currentTarget.dataset.mode

    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.mode !== mode })
    this.tabTargets.forEach((tab) => { tab.setAttribute("aria-pressed", tab.dataset.mode === mode) })
  }
}
