import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chargeType", "help", "input", "prefix"]

  connect() {
    this.codeGroup = this.hasInputTarget
      ? this.inputTarget.closest(".panel-control-group")
      : null
    this.updatePrefix()
  }

  format() {
    const input = this.hasInputTarget ? this.inputTarget : this.element
    const original = input.value
    const formatted = original
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "")

    if (original !== formatted) {
      input.value = formatted
    }
  }

  updatePrefix() {
    if (!this.hasChargeTypeTarget) return

    const chargeType = this.chargeTypeTarget.matches("select")
      ? this.chargeTypeTarget
      : this.chargeTypeTarget.querySelector("select")
    const isTax = chargeType?.value === "tax"

    if (this.hasPrefixTarget) this.prefixTarget.hidden = !isTax
    if (this.hasInputTarget) {
      if (this.codeGroup) {
        this.codeGroup.dataset.grouped = isTax.toString()

        if (isTax) {
          this.codeGroup.hidden = false
          this.codeGroup.prepend(this.inputTarget)
        } else {
          this.codeGroup.before(this.inputTarget)
          this.codeGroup.hidden = true
        }
      }

      this.inputTarget.placeholder = isTax ? "DBKK" : "SC"
    }
    if (this.hasHelpTarget) {
      this.helpTarget.textContent = isTax
        ? "Saved as TAX_DBKK. Spaces become underscores."
        : "Saved without a prefix. Spaces become underscores."
    }
  }
}
