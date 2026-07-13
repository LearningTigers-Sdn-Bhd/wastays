import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--tabs
//
// WAI-ARIA APG "tabs" pattern with automatic activation: roving tabindex, arrow/Home/End
// keys, and the active tab mirrored to a URL query param. Replaces the old `tabs` and
// `subtabs` controllers (one component, `level:` distinguishes primary vs subtab).
//
// Breadcrumb sync is done through a Stimulus **outlet** — `this.panelsUiBreadcrumbOutlets`
// are PanelsUI::Breadcrumb controllers found via the outlet selector — instead of the old
// `document.querySelector("[data-tabs-breadcrumb-label]")` global reach. No outlet on the
// page ⇒ the sync is simply skipped, keeping tabs and breadcrumb decoupled.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static outlets = ["panels-ui--breadcrumb"]
  static values = {
    active: String,
    param: { type: String, default: "tab" },
    level: { type: String, default: "primary" },
    navigation: { type: Boolean, default: false },
    syncUrl: { type: Boolean, default: true }
  }

  connect() {
    if (this.navigationValue) return this.syncNavigationFromUrl()

    const requested = this.paramValue && new URLSearchParams(window.location.search).get(this.paramValue)
    this.show(this.validTab(requested) ? requested : this.defaultTab, { updateUrl: false })
  }

  // Pointer activation.
  select(event) {
    event.preventDefault()
    this.show(event.currentTarget.dataset.tabName)
  }

  // Server-navigation tabs remain ordinary links. Update the persistent tab bar and
  // breadcrumb immediately, then allow Turbo to follow the link and replace its frame.
  selectNavigation(event) {
    this.showNavigation(event.currentTarget.dataset.tabName)
  }

  syncNavigationFromUrl() {
    const requested = this.paramValue && new URLSearchParams(window.location.search).get(this.paramValue)
    this.showNavigation(this.validTab(requested) ? requested : this.defaultTab)
  }

  showNavigation(name) {
    const activeName = this.validTab(name) ? name : this.defaultTab
    this.activeName = activeName
    let activeTab = null

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === activeName
      if (active) {
        tab.setAttribute("aria-current", "page")
        activeTab = tab
      } else {
        tab.removeAttribute("aria-current")
      }
    })

    this.syncBreadcrumb(activeTab)
  }

  // Keyboard activation (automatic — focus follows selection).
  onKeydown(event) {
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key]

    if (event.key === "Home") return this.activateByIndex(0, event)
    if (event.key === "End") return this.activateByIndex(this.tabTargets.length - 1, event)
    if (!step) return

    const names = this.tabTargets.map((tab) => tab.dataset.tabName)
    const current = names.indexOf(this.activeName)
    this.activateByIndex((current + step + names.length) % names.length, event)
  }

  activateByIndex(index, event) {
    const tab = this.tabTargets[index]
    if (!tab) return
    event.preventDefault()
    this.show(tab.dataset.tabName, { focus: true })
  }

  show(name, { updateUrl = this.syncUrlValue, focus = false } = {}) {
    const activeName = this.validTab(name) ? name : this.defaultTab
    this.activeName = activeName
    let activeTab = null

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === activeName
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
      if (active) activeTab = tab
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabPanel !== activeName)
    })

    if (focus) activeTab?.focus()
    if (updateUrl) this.updateUrl(activeName)
    this.syncBreadcrumb(activeTab)
  }

  syncBreadcrumb(tab) {
    if (!this.hasPanelsUiBreadcrumbOutlet || !tab) return

    const label = tab.dataset.tabLabel
    const showSubtab = tab.dataset.showSubtabBreadcrumb === "true"

    this.panelsUiBreadcrumbOutlets.forEach((breadcrumb) => {
      if (this.levelValue === "secondary") {
        breadcrumb.setSubtabLabel(label)
      } else {
        breadcrumb.setTabLabel(label)
        breadcrumb.setSubtabSegmentVisible(showSubtab)
      }
    })
  }

  updateUrl(name) {
    if (!this.paramValue) return

    const url = new URL(window.location)
    url.searchParams.set(this.paramValue, name)
    window.history.replaceState({}, "", url)
  }

  validTab(name) {
    return Boolean(name) && this.tabTargets.some((tab) => tab.dataset.tabName === name)
  }

  get defaultTab() {
    return this.activeValue || this.tabTargets[0]?.dataset.tabName
  }
}
