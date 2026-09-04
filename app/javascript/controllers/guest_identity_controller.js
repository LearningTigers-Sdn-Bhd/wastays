import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["country", "documentType", "numberLabel", "passportRow", "passportInput"]

  connect() {
    this.refresh()
  }

  refresh() {
    const malaysia = this.countryValue().toLowerCase() === "malaysia"
    const current = this.inputFor(this.documentTypeTarget)?.value
    const converted = malaysia && current === "national_id" ? "malaysian_nric" :
      (!malaysia && current === "malaysian_nric" ? "national_id" : current)

    this.filterOptions(malaysia)
    if (converted !== current) this.changeDocumentType(converted)
    this.renderDocumentFields(converted)
  }

  documentChanged() {
    this.renderDocumentFields(this.inputFor(this.documentTypeTarget)?.value)
  }

  countryValue() {
    return this.inputFor(this.countryTarget)?.value?.trim() || ""
  }

  inputFor(target) {
    if (!target) return null
    if (target.matches?.("input, select")) return target
    return target.querySelector("input, select")
  }

  changeDocumentType(value) {
    const input = this.inputFor(this.documentTypeTarget)
    if (!input) return
    input.value = value
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  filterOptions(malaysia) {
    const unavailable = malaysia ? "national_id" : "malaysian_nric"
    const available = malaysia ? "malaysian_nric" : "national_id"
    const root = this.documentTypeTarget.closest?.("[data-controller~='searchable-select'], [data-controller~='panels-ui--select-menu']") || this.documentTypeTarget
    root.querySelectorAll?.(`option[value="${unavailable}"], [role="option"][data-value="${unavailable}"]`).forEach((option) => {
      option.hidden = true
      option.setAttribute("aria-disabled", "true")
    })
    root.querySelectorAll?.(`option[value="${available}"], [role="option"][data-value="${available}"]`).forEach((option) => {
      option.hidden = false
      option.removeAttribute("aria-disabled")
    })
  }

  renderDocumentFields(type) {
    const nationalId = type === "national_id"
    if (this.hasPassportRowTarget) this.passportRowTarget.hidden = !nationalId
    if (this.hasPassportInputTarget) this.passportInputTarget.disabled = !nationalId
    if (this.hasNumberLabelTarget) {
      const label = this.numberLabelTarget.matches?.("label") ? this.numberLabelTarget : this.numberLabelTarget.querySelector("label")
      if (!label) return
      label.textContent = type === "passport" ? "Passport number" :
        (nationalId ? "National identity card number" : "MyKad number")
    }
  }
}
