import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "tab", "panel" ]
  static values = {
    defaultTab: String,
    parameterName: { type: String, default: "tab" }
  }

  connect() {
    const urlParams = new URLSearchParams(window.location.search)
    const requestedTab = urlParams.get(this.parameterNameValue)
    this.show(requestedTab)
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
    const activeTabName = this.validTab(tabName) ? tabName : this.defaultTab
    const activeTab = this.tabTargets.find((tab) => tab.dataset.tabName === activeTabName)

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === activeTabName
      tab.setAttribute("data-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.tabPanel === activeTabName
      panel.classList.toggle("hidden", !active)
    })

    this.updateBreadcrumbLabel(activeTab?.dataset.tabLabel)
    this.updateSubtabBreadcrumbVisibility(activeTab?.dataset.showSubtabBreadcrumb === "true")
  }

  validTab(name) {
    return name && this.tabTargets.some((tab) => tab.dataset.tabName === name)
  }

  updateBreadcrumbLabel(label) {
    const breadcrumb = document.querySelector("[data-tabs-breadcrumb-label]")
    if (breadcrumb && label) breadcrumb.textContent = label
  }

  updateSubtabBreadcrumbVisibility(visible) {
    const segment = document.querySelector("[data-subtabs-breadcrumb-segment]")
    if (segment) segment.classList.toggle("hidden", !visible)
  }

  get defaultTab() {
    return this.defaultTabValue || this.tabTargets[0]?.dataset.tabName
  }
}
