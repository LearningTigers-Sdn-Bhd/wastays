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
const MSIC_BUSINESS_DESCRIPTIONS = {
  "55101": "Hotels and resort hotels",
  "55103": "Apartment hotels / Serviced apartments",
  "55108": "Home stay operations",
  "55109": "Other short term accommodation activities"
}

export default class extends Controller {
  static targets = [
    "signatureToggle", "signingFields", "environmentSelect", "productionWarning", "confirmProductionCheckbox",
    "msicInput", "businessDescriptionInput", "businessDescriptionSuggestion", "businessDescriptionSuggestionText"
  ]

  connect() {
    this.toggleSigningFields()
    this.toggleProductionWarning()
    this.suggestBusinessDescription()
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
