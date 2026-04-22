import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["view", "button"]

  switch(event) {
    const viewName = event.currentTarget.dataset.view
    
    // Update buttons
    this.buttonTargets.forEach(btn => {
      if (btn.dataset.view === viewName) {
        btn.classList.add("bg-white", "shadow-sm", "text-indigo-600")
        btn.classList.remove("text-slate-500")
      } else {
        btn.classList.remove("bg-white", "shadow-sm", "text-indigo-600")
        btn.classList.add("text-slate-500")
      }
    })

    // Update views
    this.viewTargets.forEach(view => {
      if (view.dataset.view === viewName) {
        view.classList.remove("hidden")
      } else {
        view.classList.add("hidden")
      }
    })
  }
}
