import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "tab", "panel" ]
  static values = {
    defaultTab: String,
    parameterName: { type: String, default: "tab" }
  }

  connect() {
    const urlParams = new URLSearchParams(window.location.search)
    const urlTab = urlParams.get(this.parameterNameValue)
    const activeTab = urlTab || this.defaultTabValue
    this.show(activeTab)
  }

  switch(event) {
    event.preventDefault()
    const tabName = event.currentTarget.dataset.tabName
    this.show(tabName)
    
    // Update URL without reloading to preserve state for redirects
    const url = new URL(window.location)
    url.searchParams.set(this.parameterNameValue, tabName)
    window.history.replaceState({}, "", url)
  }

  show(tabName) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === tabName
      tab.setAttribute("data-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.tabPanel === tabName
      panel.classList.toggle("hidden", !active)
    })
  }
}
