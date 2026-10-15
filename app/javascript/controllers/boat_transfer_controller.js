import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["custom"]

  connect() {
    this.update()
  }

  update() {
    const selection = this.element.querySelector("select").value
    this.customTarget.hidden = !["charter", "own"].includes(selection)
  }
}
