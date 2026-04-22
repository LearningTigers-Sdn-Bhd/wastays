import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Check if there is a tab in the URL params
    const params = new URLSearchParams(window.location.search)
    const tabParam = params.get('tab')
    
    this.activate(tabParam || this.tabTargets[0]?.dataset.tabName || "booking-details")
  }

  switch(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.tabName)
    
    // Optional: Update URL without reloading
    const url = new URL(window.location)
    url.searchParams.set('tab', event.currentTarget.dataset.tabName)
    window.history.pushState({}, '', url)
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
