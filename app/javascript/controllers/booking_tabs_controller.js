import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.activate(this.tabTargets[0]?.dataset.tabName || "booking-details")
  }

  switch(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.tabName)
  }

  activate(name) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabName === name
      tab.classList.toggle("bg-blue-600", active)
      tab.classList.toggle("text-white", active)
      tab.classList.toggle("border-blue-600", active)
      tab.classList.toggle("bg-white", !active)
      tab.classList.toggle("text-gray-600", !active)
      tab.classList.toggle("border-gray-200", !active)
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabPanel !== name)
    })
  }
}
