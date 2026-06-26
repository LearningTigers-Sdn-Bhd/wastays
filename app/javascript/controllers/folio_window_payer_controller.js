import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folioType", "payerType", "lockedPayer", "companyAccountWrapper", "companyAccountSelect"]
  static values = { requiresCompanyAccount: Boolean, originalPayer: String }

  connect() {
    this.sync()
  }

  sync() {
    const lockedPayer = this.lockedPayerFor(this.folioTypeTarget.value)

    if (lockedPayer) {
      this.payerTypeTarget.value = lockedPayer
      this.payerTypeTarget.disabled = true
      this.lockedPayerTarget.value = lockedPayer
      this.lockedPayerTarget.disabled = false
    } else {
      this.payerTypeTarget.disabled = false
      this.lockedPayerTarget.disabled = true
      if (!this.payerTypeTarget.value) this.payerTypeTarget.value = "company"
    }

    this.syncCompanyAccount()
  }

  syncCompanyAccount() {
    if (!this.hasCompanyAccountWrapperTarget || !this.hasCompanyAccountSelectTarget) return

    const companyPayer = this.payerTypeTarget.value === "company"
    this.companyAccountWrapperTarget.hidden = !companyPayer
    this.companyAccountSelectTarget.disabled = !companyPayer
    this.companyAccountSelectTarget.required = companyPayer && this.requiresCompanyAccount()
    if (!companyPayer) this.companyAccountSelectTarget.value = ""
  }

  requiresCompanyAccount() {
    return this.requiresCompanyAccountValue || this.originalPayerValue !== "company"
  }

  lockedPayerFor(folioType) {
    if (folioType === "guest") return "guest"
    if (folioType === "house") return "hotel"

    return null
  }
}
