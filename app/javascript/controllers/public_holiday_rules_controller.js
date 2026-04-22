import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "container", "template" ]
  static values = { index: Number }

  connect() {
    if (!this.hasIndexValue) {
      this.indexValue = this.containerTarget.children.length
    }
  }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", this.indexValue)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
    this.indexValue += 1
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-public-holiday-row]")
    if (row) row.remove()
  }
}
