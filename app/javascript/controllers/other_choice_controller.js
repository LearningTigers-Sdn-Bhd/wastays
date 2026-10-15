import { Controller } from "@hotwired/stimulus"

// Shows a text field when a select is set to its "other" value, such as a
// bank that is not in the list. A hidden field is also disabled, so it does
// not submit and its `required` does not block the form.
export default class extends Controller {
  static targets = ["field", "input"]
  static values = { other: String }

  toggle(event) {
    if (!event.target.matches("select")) return

    const show = event.target.value === this.otherValue
    this.fieldTarget.hidden = !show
    this.inputTarget.disabled = !show
  }
}
