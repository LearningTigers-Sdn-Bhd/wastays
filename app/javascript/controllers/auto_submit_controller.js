import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    if (event?.target?.value?.trim() === "") {
      this.element.requestSubmit()
      return
    }

    this.element.requestSubmit()
  }

  submitNow() {
    this.element.requestSubmit()
  }
}
