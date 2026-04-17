import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.timeout = null
  }

  submit() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    this.timeout = window.setTimeout(() => {
      if (typeof this.element.requestSubmit === "function") {
        this.element.requestSubmit()
      } else {
        this.element.submit()
      }
    }, 300)
  }

  submitNow() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }

    if (typeof this.element.requestSubmit === "function") {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }
}
