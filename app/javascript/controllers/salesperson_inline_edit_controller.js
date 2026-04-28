import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "nameDisplay", "nameInput", "emailDisplay", "emailInput", "hotelDisplay", "hotelSelector", "readonlyActions", "editActions", "primaryButton"]
  static values = { startEditing: Boolean }

  connect() {
    this.editing = false
    this.setEditing(this.hasStartEditingValue && this.startEditingValue)
  }

  primaryAction() {
    if (this.editing) {
      this.formTarget.requestSubmit()
    } else {
      this.setEditing(true, { focus: true })
    }
  }

  cancel(event) {
    event.preventDefault()
    this.formTarget.reset()
    this.setEditing(false)
  }

  setEditing(editing, { focus = false } = {}) {
    this.editing = editing

    this.nameDisplayTarget.classList.toggle("hidden", editing)
    this.nameInputTarget.classList.toggle("hidden", !editing)
    this.nameInputTarget.disabled = !editing
    this.nameInputTarget.classList.toggle("bg-slate-50", !editing)
    this.nameInputTarget.classList.toggle("text-slate-500", !editing)
    this.nameInputTarget.classList.toggle("cursor-not-allowed", !editing)
    this.nameInputTarget.classList.toggle("bg-white", editing)
    this.nameInputTarget.classList.toggle("text-slate-700", editing)

    this.emailDisplayTarget.classList.toggle("hidden", editing)
    this.emailInputTarget.classList.toggle("hidden", !editing)
    this.emailInputTarget.disabled = !editing
    this.emailInputTarget.classList.toggle("bg-slate-50", !editing)
    this.emailInputTarget.classList.toggle("text-slate-500", !editing)
    this.emailInputTarget.classList.toggle("cursor-not-allowed", !editing)
    this.emailInputTarget.classList.toggle("bg-white", editing)
    this.emailInputTarget.classList.toggle("text-slate-700", editing)

    this.hotelDisplayTarget.classList.toggle("hidden", editing)
    this.hotelSelectorTarget.hidden = !editing
    this.hotelSelectorTarget.classList.toggle("hidden", !editing)

    const dropdownButton = this.hotelSelectorTarget.querySelector("button")
    if (dropdownButton) {
      dropdownButton.disabled = !editing
      dropdownButton.classList.toggle("cursor-not-allowed", !editing)
      dropdownButton.classList.toggle("opacity-70", !editing)
    }

    this.hotelSelectorTarget.querySelectorAll("input[type='checkbox']").forEach((checkbox) => {
      checkbox.disabled = !editing
    })

    const dropdownMenu = this.hotelSelectorTarget.querySelector('[data-dropdown-target="menu"]')
    if (dropdownMenu) {
      dropdownMenu.classList.add("hidden")
    }

    this.readonlyActionsTarget.classList.toggle("hidden", editing)
    this.editActionsTarget.classList.toggle("hidden", !editing)
    this.primaryButtonTarget.textContent = editing ? "Save" : "Edit"

    if (editing && focus) {
      this.nameInputTarget.focus()
      this.nameInputTarget.select()
    }
  }
}
