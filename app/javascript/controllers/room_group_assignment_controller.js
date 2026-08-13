import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group", "newGroupField"]

  connect() {
    this.toggleNewGroup()
  }

  toggleNewGroup() {
    const creating = this.groupTarget.querySelector("select")?.value === "new"
    this.newGroupFieldTarget.hidden = !creating

    const input = this.newGroupFieldTarget.querySelector("input")
    if (input) input.required = creating
  }
}
