import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "editButton"]
  static values = { applied: Boolean }

  connect() {
    if (this.appliedValue && this.inputTarget.value.trim() !== "") {
      this.showApplied()
    } else {
      this.showEditing()
    }
  }

  toggle() {
    this.buttonTarget.classList.toggle("hidden", this.inputTarget.value.trim() === "")
  }

  edit() {
    this.showEditing()
    this.inputTarget.focus()
  }

  showApplied() {
    this.inputTarget.readOnly = true
    this.buttonTarget.classList.add("hidden")
    this.editButtonTarget.classList.remove("hidden")
  }

  showEditing() {
    this.inputTarget.readOnly = false
    this.editButtonTarget.classList.add("hidden")
    this.toggle()
  }
}
