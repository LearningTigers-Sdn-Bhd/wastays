import { Controller } from "@hotwired/stimulus"

// Keeps the folio Type / Payer / Company-account trio consistent while editing
// a folio window.
//
// The three fields render as PanelsUI::SelectMenu, which owns the data
// attributes on its native <select>. So the targets here are the FormField
// wrappers, and the native select inside each is resolved by tag. The native
// select stays the source of truth; dispatching `change` on it lets the
// select-menu controller re-sync its visible trigger.
//
// A guest or house folio has no payer choice, so the payer field is hidden and
// the disabled `lockedPayer` input takes over the parameter — hiding rather
// than disabling the select-menu keeps the submitted params identical without
// driving another controller's disabled state from outside.
export default class extends Controller {
  static targets = ["folioType", "payerType", "lockedPayer", "companyAccount"]
  static values = { requiresCompanyAccount: Boolean, originalPayer: String }

  connect() {
    this.sync()
  }

  sync() {
    const lockedPayer = this.lockedPayerFor(this.selectFor(this.folioTypeTarget).value)

    if (lockedPayer) {
      this.setSelectValue(this.payerTypeTarget, lockedPayer)
      this.payerTypeTarget.hidden = true
      this.selectFor(this.payerTypeTarget).disabled = true
      this.lockedPayerTarget.value = lockedPayer
      this.lockedPayerTarget.disabled = false
    } else {
      this.payerTypeTarget.hidden = false
      this.selectFor(this.payerTypeTarget).disabled = false
      this.lockedPayerTarget.disabled = true
      if (!this.selectFor(this.payerTypeTarget).value) this.setSelectValue(this.payerTypeTarget, "company")
    }

    this.syncCompanyAccount()
  }

  syncCompanyAccount() {
    if (!this.hasCompanyAccountTarget) return

    const select = this.selectFor(this.companyAccountTarget)
    const companyPayer = this.effectivePayer === "company"

    this.companyAccountTarget.hidden = !companyPayer
    select.disabled = !companyPayer
    select.required = companyPayer && this.requiresCompanyAccount()
    if (!companyPayer) this.setSelectValue(this.companyAccountTarget, "")
  }

  get effectivePayer() {
    return this.lockedPayerTarget.disabled ? this.selectFor(this.payerTypeTarget).value : this.lockedPayerTarget.value
  }

  selectFor(wrapper) {
    return wrapper.querySelector("select")
  }

  setSelectValue(wrapper, value) {
    const select = this.selectFor(wrapper)
    if (select.value === value) return

    select.value = value
    select.dispatchEvent(new Event("change", { bubbles: true }))
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
