import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "tab", "panel" ]

  connect() {
    this.show("gp")
  }

  switch(event) {
    event.preventDefault()
    this.show(event.currentTarget.dataset.tier)
  }

  show(tier) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tier === tier
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.classList.toggle("bg-slate-900", active)
      tab.classList.toggle("text-white", active)
      tab.classList.toggle("border-slate-900", active)
      tab.classList.toggle("bg-white", !active)
      tab.classList.toggle("text-slate-600", !active)
      tab.classList.toggle("border-slate-200", !active)
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tier !== tier)
    })
  }
}
