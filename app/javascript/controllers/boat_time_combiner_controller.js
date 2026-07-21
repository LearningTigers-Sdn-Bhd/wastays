import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dateInput", "timeInput", "datetimeInput"]

  combine() {
    const date = this.dateInputTarget.value
    const time = this.timeInputTarget.value

    if (date && time) {
      this.datetimeInputTarget.value = `${date}T${time}`
    } else {
      this.datetimeInputTarget.value = ""
    }

    this.datetimeInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.datetimeInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
