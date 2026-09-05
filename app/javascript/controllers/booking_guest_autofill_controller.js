import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "nameField", "emailField", "phoneField", "dateOfBirthField", "genderField", "countryField",
    "existingGuestId", "profileRow", "linkedName", "linkedDescription", "blacklistWarning", "updateSwitch",
    "addressField", "addressInput", "cityField", "stateField", "postalCodeField",
    "addressCountryField", "addressToggle",
    "identityField", "identityToggle",
    "documentTypeField", "governmentIdField", "passportNumberField", "tinField"
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
    if (this.hasCityFieldTarget) this.setControl(this.cityFieldTarget, guest.city)
    // The country goes in first. It decides whether the state field is the
    // Malaysian code list or a free text box, so the state must be written
    // after the right control is on screen.
    if (this.hasAddressCountryFieldTarget) this.setControl(this.addressCountryFieldTarget, guest.address_country)
    if (this.hasStateFieldTarget) this.setControl(this.stateFieldTarget, guest.state_code)
    if (this.hasPostalCodeFieldTarget) this.setControl(this.postalCodeFieldTarget, guest.postal_code)
    if (guest.city || guest.state_code || guest.postal_code || guest.address_country) this.showAddress()

    // The document type goes in first. guest-identity reads it to enable the
    // passport field and to rename the number label, so the two number fields
    // must be written after that control has settled.
    if (this.hasDocumentTypeFieldTarget) this.setControl(this.documentTypeFieldTarget, guest.document_type)
    if (this.hasGovernmentIdFieldTarget) this.setControl(this.governmentIdFieldTarget, guest.government_id)
    if (this.hasPassportNumberFieldTarget) this.setControl(this.passportNumberFieldTarget, guest.passport_number)
    if (guest.document_type || guest.government_id || guest.passport_number) this.showIdentity()
    // Only a sheet that offers a tax number gets one. The booking sheet takes
    // the stay's number on the billing rail, not here.
    if (this.hasTinFieldTarget) this.setControl(this.tinFieldTarget, guest.tin)

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
    // A container may hold two controls for one field — the state is a code
    // list or a text box depending on the country. Only one is ever enabled,
    // so fill that one.
    const control = container.querySelector("input:not([disabled]), select:not([disabled])") ||
      container.querySelector("input, select")
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

  toggleIdentity(event) {
    event.preventDefault()
    this.showIdentity({ focus: true })
  }

  // Picking a guest opens the block as a side effect, so focus moves only when
  // the desk pressed the button itself.
  showIdentity({ focus = false } = {}) {
    if (!this.hasIdentityFieldTarget) return
    this.identityFieldTarget.hidden = false
    if (this.hasIdentityToggleTarget) this.identityToggleTarget.hidden = true
    if (focus) this.identityFieldTarget.querySelector("select, input")?.focus()
  }

  toggleAddress(event) {
    event.preventDefault()
    this.showAddress({ focus: true })
  }

  // Picking a guest opens the block as a side effect, so focus moves only when
  // the desk pressed the button itself. A sheet that shows the address from the
  // start has no button, and must not have the caret pulled out of the name.
  showAddress({ focus = false } = {}) {
    if (!this.hasAddressFieldTarget) return
    this.addressFieldTarget.hidden = false
    if (this.hasAddressToggleTarget) this.addressToggleTarget.hidden = true
    if (focus && this.hasAddressInputTarget) this.addressInputTarget.focus()
  }
}
