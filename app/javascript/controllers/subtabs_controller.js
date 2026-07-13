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
    const activeTab = this.validTab(requestedTab) ? requestedTab : this.defaultTab
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
    const activeTab = this.tabTargets.find((tab) => tab.dataset.tabName === tabName)

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === tabName
      tab.setAttribute("data-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.tabPanel === tabName
      panel.classList.toggle("hidden", !active)
    })

    this.updateBreadcrumbLabel(activeTab?.dataset.tabLabel)
  }

  validTab(name) {
    return name && this.tabTargets.some((tab) => tab.dataset.tabName === name)
  }

  updateBreadcrumbLabel(label) {
    if (!label) return

    // Multiple subtabs controllers can exist on one page (one per top-level
    // tab). Only the one whose enclosing top-level panel is currently
    // visible should own the shared breadcrumb label, otherwise a hidden
    // group's default tab silently overwrites the active tab's label.
    const panel = this.element.closest("[data-tabs-target='panel']")
    if (panel && panel.classList.contains("hidden")) return

    const breadcrumb = document.querySelector("[data-subtabs-breadcrumb-label]")
    if (breadcrumb) breadcrumb.textContent = label
  }

  get defaultTab() {
    return this.defaultTabValue || this.tabTargets[0]?.dataset.tabName
  }

  togglePricingInput(event) {
    const value = event.currentTarget.value
    const form = event.currentTarget.closest("form")
    if (form) {
      const pricingValDiv = form.querySelector(".pricing-value-input")
      if (pricingValDiv) {
        pricingValDiv.classList.toggle("hidden", value === "same")
      }
    }
  }
}
