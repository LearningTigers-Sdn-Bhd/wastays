import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const urlParams = new URLSearchParams(window.location.search)
    const activeTab = urlParams.get("tab") || this.tabTargets[0]?.dataset.tabName || "booking-details"
    this.activate(activeTab)
  }

  switch(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.tabName)
  }

  activate(name) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === name
      tab.setAttribute("data-active", active)
      
      // We'll use CSS/Tailwind data-active variants in the HTML
      // but keeping some logic here for safety if data attributes aren't enough
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabPanel !== name)
    })
  }
}
