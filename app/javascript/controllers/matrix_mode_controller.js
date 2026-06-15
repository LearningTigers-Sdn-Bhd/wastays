import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewOnly", "editOnly", "saveSection", "editButton"]

  enableEdit(event) {
    if (event) event.preventDefault()
    this.toggleMode(true)
  }

  disableEdit(event) {
    if (event) event.preventDefault()
    this.toggleMode(false)
  }

  toggleMode(editing) {
    this.viewOnlyTargets.forEach(el => el.classList.toggle("hidden", editing))
    this.editOnlyTargets.forEach(el => el.classList.toggle("hidden", !editing))
    this.saveSectionTarget.classList.toggle("hidden", !editing)
    this.editButtonTarget.classList.toggle("hidden", editing)
  }
}
