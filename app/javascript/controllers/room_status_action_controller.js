import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["readyPanel", "readyInput", "failPanel", "failInput"]

  openReady(event) {
    if (event) event.preventDefault()
    if (this.hasFailPanelTarget) this.failPanelTarget.hidden = true
    if (this.hasReadyPanelTarget) {
      this.readyPanelTarget.hidden = false
      requestAnimationFrame(() => this.readyInputTarget?.focus())
    }
  }

  openFail(event) {
    if (event) event.preventDefault()
    if (this.hasReadyPanelTarget) this.readyPanelTarget.hidden = true
    if (this.hasFailPanelTarget) {
      this.failPanelTarget.hidden = false
      requestAnimationFrame(() => this.failInputTarget?.focus())
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasReadyPanelTarget) {
      this.readyPanelTarget.hidden = true
      if (this.hasReadyInputTarget) this.readyInputTarget.value = ""
    }
    if (this.hasFailPanelTarget) {
      this.failPanelTarget.hidden = true
      if (this.hasFailInputTarget) this.failInputTarget.value = ""
    }
  }
}
