import { Controller } from "@hotwired/stimulus"

// Shows the closed-date override only while the posting date is before the
// hotel's current business date. The reason field shows only while the switch
// is on. Hidden fields are disabled so they do not submit.
// ISO dates (YYYY-MM-DD) sort as strings, so a string compare is enough.
export default class extends Controller {
  static targets = ["postingDate", "box", "toggle", "reason"]
  static values = { currentBusinessDate: String }

  connect() {
    this.update()
  }

  update() {
    const date = this.postingDateTarget.value
    const past = date !== "" && date < this.currentBusinessDateValue
    const switchInput = this.toggleTarget.querySelector("input[type='checkbox']")
    const reasonShown = past && switchInput.checked

    this.boxTarget.hidden = !past
    this.toggleTarget.querySelectorAll("input").forEach((input) => { input.disabled = !past })
    this.reasonTarget.hidden = !reasonShown
    this.reasonTarget.querySelectorAll("input").forEach((input) => { input.disabled = !reasonShown })
  }
}
