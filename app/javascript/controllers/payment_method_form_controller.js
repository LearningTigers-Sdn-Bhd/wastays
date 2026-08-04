import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["code", "type", "guestAdvance", "defaultCash", "surchargeEnabled", "surchargeFields"]

  connect() {
    this.update()
  }

  formatCode() {
    this.codeTarget.value = this.codeTarget.value
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 10)
  }

  update() {
    const type = this.checkedValue(this.typeTarget)
    const guestAdvance = this.checked(this.guestAdvanceTarget)
    const surchargeEnabled = this.checked(this.surchargeEnabledTarget)

    this.defaultCashTarget.hidden = type !== "cash" || guestAdvance
    this.surchargeFieldsTarget.hidden = !surchargeEnabled
    this.surchargeFieldsTarget.querySelectorAll("input, select, button").forEach((control) => {
      control.disabled = !surchargeEnabled
    })
  }

  checkedValue(target) {
    return target.querySelector("input[type='radio']:checked")?.value
  }

  checked(target) {
    const input = target.matches("input") ? target : target.querySelector("input[type='checkbox']")
    return input?.checked || false
  }
}
