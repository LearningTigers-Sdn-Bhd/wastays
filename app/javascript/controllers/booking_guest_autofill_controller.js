import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "nameField", "emailField", "phoneField", "dateOfBirthField", "genderField", "countryField",
    "existingGuestId", "profileRow", "linkedName", "linkedDescription", "blacklistWarning", "updateSwitch",
    "addressField", "addressInput", "addressToggle"
  ]

  selectGuest(event) {
    const result = event.detail?.result
    if (!result?.value) return

    const guest = result.data || {}
    this.setControl(this.nameFieldTarget, guest.name)
    this.setControl(this.emailFieldTarget, guest.email)
    this.setControl(this.phoneFieldTarget, guest.phone)
    this.setControl(this.dateOfBirthFieldTarget, guest.date_of_birth)
    this.setControl(this.genderFieldTarget, guest.gender)
    this.setControl(this.countryFieldTarget, guest.country)
    if (this.hasAddressInputTarget && guest.home_address) {
      this.addressInputTarget.value = guest.home_address
      this.addressInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.showAddress()
    }

    this.existingGuestIdTarget.value = result.value
    this.linkedNameTarget.textContent = guest.name || result.label || "Existing guest"
    this.linkedDescriptionTarget.textContent = [guest.email, guest.phone].filter(Boolean).join(" · ")
    this.blacklistWarningTarget.hidden = !guest.blacklisted
    this.profileRowTarget.hidden = false
    this.setUpdateEnabled(false)
  }

  clearGuest(event) {
    event.preventDefault()
    this.existingGuestIdTarget.value = ""
    this.profileRowTarget.hidden = true
    this.blacklistWarningTarget.hidden = true
    this.setUpdateEnabled(false)
    this.nameFieldTarget.querySelector("input")?.focus()
  }

  setControl(container, value) {
    const control = container.querySelector("input, select")
    if (!control) return

    control.value = value || ""
    control.dispatchEvent(new Event("input", { bubbles: true }))
    control.dispatchEvent(new Event("change", { bubbles: true }))

    const datePicker = container.matches(".panel-date-picker") ? container : container.querySelector(".panel-date-picker")
    if (datePicker) {
      const controller = this.application.getControllerForElementAndIdentifier(datePicker, "panels-ui--date-picker")
      controller?.resetFromInput()
    }
  }

  setUpdateEnabled(enabled) {
    if (!this.hasUpdateSwitchTarget) return
    this.updateSwitchTarget.checked = enabled
    this.updateSwitchTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  toggleAddress(event) {
    event.preventDefault()
    this.showAddress()
  }

  showAddress() {
    if (!this.hasAddressFieldTarget) return
    this.addressFieldTarget.hidden = false
    if (this.hasAddressToggleTarget) this.addressToggleTarget.hidden = true
    this.addressInputTarget?.focus()
  }
}
