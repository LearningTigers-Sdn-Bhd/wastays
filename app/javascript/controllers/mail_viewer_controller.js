import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["view", "button"]

  switch(event) {
    const viewName = event.currentTarget.dataset.view

    this.buttonTargets.forEach((button) => {
      const selected = button.dataset.view === viewName
      button.setAttribute("aria-pressed", selected.toString())
      button.classList.toggle("is-active", selected)
    })

    this.viewTargets.forEach((view) => {
      view.hidden = view.dataset.view !== viewName
    })
  }
}
