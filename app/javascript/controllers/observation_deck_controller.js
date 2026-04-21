import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "form"]

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.formTarget.requestSubmit()
    }, 300)
  }

  toggleJson(event) {
    const target = event.currentTarget
    const content = target.nextElementSibling
    content.classList.toggle('hidden')
    target.querySelector('svg').classList.toggle('rotate-90')
  }
}
