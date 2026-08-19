import { Controller } from "@hotwired/stimulus"

// The signing certificate and key are only meaningful once a hotel has
// switched digital signing on, so they stay out of the way until then.
export default class extends Controller {
  static targets = ["signatureToggle", "signingFields"]

  connect() {
    this.toggleSigningFields()
  }

  toggleSigningFields() {
    if (!this.hasSignatureToggleTarget || !this.hasSigningFieldsTarget) return

    this.signingFieldsTarget.hidden = !this.signatureToggleTarget.checked
  }
}
