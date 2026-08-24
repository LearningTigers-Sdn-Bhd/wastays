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
export default class extends Controller {
  static targets = ["signatureToggle", "signingFields", "environmentSelect", "productionWarning", "confirmProductionCheckbox"]

  connect() {
    this.toggleSigningFields()
    this.toggleProductionWarning()
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
