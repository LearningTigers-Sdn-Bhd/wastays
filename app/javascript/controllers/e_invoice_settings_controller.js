import { Controller } from "@hotwired/stimulus"

// The signing certificate and key are only meaningful once a hotel has
// switched digital signing on, so they stay out of the way until then.
//
// Currently dormant: the "Sign documents digitally" switch and the signing
// fields were removed from _e_invoice_section.html.erb on 2026-08-20 because
// EInvoice::DocumentSigner doesn't produce a signature LHDN accepts yet (see
// the comment in that view file for details). Both Stimulus targets are
// optional (see the hasXTarget guards below), so this controller is a no-op
// until that markup comes back - nothing here needs to change to restore it.

// LHDN's recommended MSIC descriptions for the codes accommodation
// businesses on this platform actually use (see
// https://sdk.myinvois.hasil.gov.my/codes/msic-codes/ for the full list).
// Mirrors EInvoice::MsicCodes::CODES - keep the two in sync.
const MSIC_BUSINESS_DESCRIPTIONS = {
  "55101": "Hotels and resort hotels",
  "55103": "Apartment hotels / Serviced apartments",
  "55108": "Home stay operations",
  "55109": "Other short term accommodation activities"
}

const MSIC_CUSTOM = "custom"

export default class extends Controller {
  static targets = [
    "signatureToggle", "signingFields", "environmentSelect", "productionWarning", "confirmProductionCheckbox",
    "msicCodePicker", "msicInputWrapper", "msicInput", "businessDescriptionInput", "businessDescriptionSuggestion", "businessDescriptionSuggestionText"
  ]

  connect() {
    this.toggleSigningFields()
    this.toggleProductionWarning()
    this.suggestBusinessDescription()
  }

  // The picker is a shortcut over the real MSIC code field, not a separate
  // source of truth - picking a known code fills the field (and offers its
  // description) while keeping it out of the way; picking "Custom" reveals
  // the field and hands it focus so the hotel can type a code that isn't in
  // the list. The field stays in the DOM either way, pre-filled, so its
  // value still submits when hidden.
  pickMsicCode() {
    if (!this.hasMsicCodePickerTarget || !this.hasMsicInputTarget) return

    const value = this.msicCodePickerTarget.value

    if (value === "" ) return

    if (value === MSIC_CUSTOM) {
      this.msicInputTarget.value = ""
      if (this.hasMsicInputWrapperTarget) this.msicInputWrapperTarget.hidden = false
      this.msicInputTarget.focus()
    } else {
      this.msicInputTarget.value = value
      if (this.hasMsicInputWrapperTarget) this.msicInputWrapperTarget.hidden = true
    }

    this.suggestBusinessDescription()
  }

  // Keeps the picker showing the right option when the code field is edited
  // directly - a known code selects itself, anything else falls to "Custom".
  syncMsicCodePicker() {
    if (!this.hasMsicCodePickerTarget || !this.hasMsicInputTarget) return

    const code = this.msicInputTarget.value.trim()
    const knownCode = Object.prototype.hasOwnProperty.call(MSIC_BUSINESS_DESCRIPTIONS, code)

    this.msicCodePickerTarget.value = code === "" ? "" : (knownCode ? code : MSIC_CUSTOM)
  }

  // Offers LHDN's recommended wording for a known MSIC code rather than
  // filling it in automatically - the hotel may already have its own
  // description on file, so this stays a one-click suggestion, not an
  // overwrite.
  suggestBusinessDescription() {
    if (!this.hasMsicInputTarget || !this.hasBusinessDescriptionSuggestionTarget) return

    const description = MSIC_BUSINESS_DESCRIPTIONS[this.msicInputTarget.value.trim()]

    if (description) {
      this.businessDescriptionSuggestionTextTarget.textContent = description
      this.businessDescriptionSuggestionTarget.hidden = false
    } else {
      this.businessDescriptionSuggestionTarget.hidden = true
    }
  }

  applyBusinessDescriptionSuggestion() {
    if (!this.hasBusinessDescriptionInputTarget) return

    this.businessDescriptionInputTarget.value = this.businessDescriptionSuggestionTextTarget.textContent
    this.businessDescriptionSuggestionTarget.hidden = true
  }

  toggleSigningFields() {
    if (!this.hasSignatureToggleTarget || !this.hasSigningFieldsTarget) return

    this.signingFieldsTarget.hidden = !this.signatureToggleTarget.checked
  }

  // Reveals the "this files real e-invoices" warning + confirmation checkbox
  // only while "production" is selected. This is a UX nicety only - the
  // actual enforcement is server-side, in
  // HotelPortal::EInvoiceSettingsForm#going_to_production_without_confirmation?,
  // so a request that skips this JS entirely still gets refused.
  toggleProductionWarning() {
    if (!this.hasEnvironmentSelectTarget || !this.hasProductionWarningTarget) return

    const isProduction = this.environmentSelectTarget.value === "production"
    this.productionWarningTarget.hidden = !isProduction

    // Unchecking (and hiding) the box when the hotel switches back off
    // production means it can't be left checked from an earlier attempt and
    // silently satisfy the server-side check next time this is production.
    if (!isProduction && this.hasConfirmProductionCheckboxTarget) {
      this.confirmProductionCheckboxTarget.checked = false
    }
  }
}
