import { Controller } from "@hotwired/stimulus"

// Flips the permission matrix between reading and editing. Both modes share the
// same spot in the header, so the control the operator just pressed disappears —
// focus has to be handed to the one that replaced it.
export default class extends Controller {
  static targets = ["viewOnly", "editOnly", "editTrigger", "cancelTrigger", "status"]

  enableEdit(event) {
    if (event) event.preventDefault()
    this.toggleMode(true)
    if (this.hasCancelTriggerTarget) this.cancelTriggerTarget.focus()
  }

  disableEdit(event) {
    if (event) event.preventDefault()
    this.restoreCheckboxes()
    this.toggleMode(false)
    if (this.hasEditTriggerTarget) this.editTriggerTarget.focus()
  }

  toggleMode(editing) {
    this.viewOnlyTargets.forEach(el => el.classList.toggle("hidden", editing))
    this.editOnlyTargets.forEach(el => el.classList.toggle("hidden", !editing))
    this.announce(editing ? "Editing permissions." : "Editing cancelled. No changes were saved.")
  }

  // Cancel discards. Without this the boxes keep the abandoned edits while the
  // icons they hide behind still report the saved state.
  restoreCheckboxes() {
    this.editOnlyTargets.forEach(el => {
      el.querySelectorAll("input[type=checkbox]").forEach(box => {
        box.checked = box.defaultChecked
      })
    })
  }

  announce(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
