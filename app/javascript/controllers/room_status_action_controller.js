import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["readyPanel", "readyInput", "failPanel", "failInput", "priorityPanel", "priorityInput"]

  openReady(event) {
    if (event) event.preventDefault()
    this.closeAll()
    if (this.hasReadyPanelTarget) {
      this.readyPanelTarget.hidden = false
      requestAnimationFrame(() => this.readyInputTarget?.focus())
    }
  }

  openFail(event) {
    if (event) event.preventDefault()
    this.closeAll()
    if (this.hasFailPanelTarget) {
      this.failPanelTarget.hidden = false
      requestAnimationFrame(() => this.failInputTarget?.focus())
    }
  }

  openPriority(event) {
    if (event) event.preventDefault()
    this.closeAll()
    if (this.hasPriorityPanelTarget) {
      this.priorityPanelTarget.hidden = false
      requestAnimationFrame(() => this.priorityInputTarget?.focus())
    }
  }

  close(event) {
    if (event) event.preventDefault()
    this.closeAll()
  }

  closeAll() {
    if (this.hasReadyPanelTarget) {
      this.readyPanelTarget.hidden = true
      if (this.hasReadyInputTarget) this.readyInputTarget.value = ""
    }
    if (this.hasFailPanelTarget) {
      this.failPanelTarget.hidden = true
      if (this.hasFailInputTarget) this.failInputTarget.value = ""
    }
    if (this.hasPriorityPanelTarget) {
      this.priorityPanelTarget.hidden = true
      if (this.hasPriorityInputTarget) this.priorityInputTarget.value = ""
    }
  }
}
