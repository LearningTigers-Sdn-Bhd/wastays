import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 400 }
  }

  connect() {
    this.timeout = null
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  submit(event) {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    this.timeout = window.setTimeout(() => {
      this.submitNow()
    }, this.delayValue)
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
