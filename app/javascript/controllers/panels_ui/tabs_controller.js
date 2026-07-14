import { Controller } from "@hotwired/stimulus"

// WAI-ARIA panel tabs. Link navigation is rendered without this controller.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    active: String,
    param: { type: String, default: "" }
  }

  connect() {
    const requested = this.paramValue && new URLSearchParams(window.location.search).get(this.paramValue)
    const initial = this.validTab(requested) ? requested : this.defaultTab
    this.show(initial, { updateUrl: false, dispatch: false })
  }

  select(event) {
    event.preventDefault()
    this.show(event.currentTarget.dataset.tabName)
  }

  onKeydown(event) {
    if (event.key === "Home") return this.activateByIndex(0, event)
    if (event.key === "End") return this.activateByIndex(this.tabTargets.length - 1, event)

    const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key]
    if (!step) return

    const current = this.tabTargets.findIndex((tab) => tab.dataset.tabName === this.activeName)
    this.activateByIndex((current + step + this.tabTargets.length) % this.tabTargets.length, event)
  }

  activateByIndex(index, event) {
    const tab = this.tabTargets[index]
    if (!tab) return

    event.preventDefault()
    this.show(tab.dataset.tabName, { focus: true })
  }

  show(name, { updateUrl = Boolean(this.paramValue), focus = false, dispatch = true } = {}) {
    const activeName = this.validTab(name) ? name : this.defaultTab
    this.activeName = activeName
    let activeTab = null
    let activePanel = null

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === activeName
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
      if (active) activeTab = tab
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.tabPanel === activeName
      panel.hidden = !active
      if (active) activePanel = panel
    })

    if (focus) activeTab?.focus()
    if (updateUrl) this.updateUrl(activeName)
    if (dispatch) this.dispatchChange(activeName, activeTab, activePanel)
  }

  dispatchChange(name, trigger, panel) {
    window.dispatchEvent(new CustomEvent("panels-ui--tabs:change", {
      detail: {
        id: this.element.id,
        name,
        label: trigger?.dataset.tabLabel,
        trigger,
        panel
      }
    }))
  }

  updateUrl(name) {
    const url = new URL(window.location)
    url.searchParams.set(this.paramValue, name)
    window.history.replaceState(window.history.state, "", url)
  }

  validTab(name) {
    return Boolean(name) && this.tabTargets.some((tab) => tab.dataset.tabName === name)
  }

  get defaultTab() {
    return this.validTab(this.activeValue) ? this.activeValue : this.tabTargets[0]?.dataset.tabName
  }
}
