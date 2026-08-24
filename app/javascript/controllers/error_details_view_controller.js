import { Controller } from "@hotwired/stimulus"

// Toggles between a plain-language list of rejection reasons and the raw
// JSON LHDN/MyInvois returned, for hotel staff who don't need (or want) to
// read a developer-style error payload to understand what went wrong.
export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    this.show(event.currentTarget.dataset.view)
  }

  show(view) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.view === view
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.classList.toggle("bg-card", active)
      tab.classList.toggle("text-foreground", active)
      tab.classList.toggle("shadow-sm", active)
      tab.classList.toggle("text-muted-foreground", !active)
    })

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.view !== view
    })
  }
}
