import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { indeterminate: Boolean }

  connect() {
    this.inputTarget.indeterminate = this.indeterminateValue
  }

  clearIndeterminate() {
    this.inputTarget.indeterminate = false
  }
}
