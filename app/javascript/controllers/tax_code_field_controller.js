import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chargeType", "help", "input", "prefix"]

  connect() {
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

    const isTax = this.chargeTypeTarget.value === "tax"
    if (this.hasPrefixTarget) this.prefixTarget.hidden = !isTax
    if (this.hasInputTarget) {
      this.inputTarget.classList.toggle("rounded-r-xl", isTax)
      this.inputTarget.classList.toggle("rounded-xl", !isTax)
    }
    if (this.hasHelpTarget) {
      this.helpTarget.textContent = isTax
        ? "Used as transaction code suffix. Example: DBKK becomes TAX_DBKK. Spaces become underscores."
        : "Used as transaction code. Example: SC stays SC. Spaces become underscores."
    }
  }
}
