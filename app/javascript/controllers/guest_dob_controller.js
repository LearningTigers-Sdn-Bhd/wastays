import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["country", "documentType", "governmentId", "dateOfBirth"]

  autofill() {
    if (!this.readyForAutofill()) return

    const parsedDate = this.parseMalaysianIcDateOfBirth(this.governmentIdTarget.value)
    if (parsedDate) this.dateOfBirthTarget.value = parsedDate
  }

  readyForAutofill() {
    if (!this.hasGovernmentIdTarget || !this.hasDateOfBirthTarget) return false
    if (this.dateOfBirthTarget.value.trim() !== "") return false

    const country = this.resolveCountry()
    const docType = this.resolveDocumentType()
    if (!country || !docType) return false

    return country === "malaysia" && docType === "ic"
  }

  resolveCountry() {
    if (this.hasCountryTarget) return this.countryTarget.value.trim().toLowerCase()
    const form = this.element.closest("form")
    if (!form) return null
    const el = form.querySelector('[data-guest-field="country"]')
    return el ? el.value.trim().toLowerCase() : null
  }

  resolveDocumentType() {
    if (this.hasDocumentTypeTarget) return this.documentTypeTarget.value
    const form = this.element.closest("form")
    if (!form) return null
    const el = form.querySelector('[data-guest-field="document_type"]')
    return el ? el.value : null
  }

  parseMalaysianIcDateOfBirth(governmentId) {
    const digits = (governmentId || "").replace(/\D/g, "").slice(0, 6)
    if (digits.length < 6) return null

    const today = new Date()
    const currentCentury = Math.floor(today.getFullYear() / 100) * 100
    const year = currentCentury + Number.parseInt(digits.slice(0, 2), 10)
    const month = Number.parseInt(digits.slice(2, 4), 10)
    const day = Number.parseInt(digits.slice(4, 6), 10)

    let date = new Date(Date.UTC(year, month - 1, day))
    if (
      Number.isNaN(date.getTime()) ||
      date.getUTCMonth() + 1 !== month ||
      date.getUTCDate() !== day
    ) {
      return null
    }

    const todayUtc = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()))
    if (date > todayUtc) {
      date = new Date(Date.UTC(year - 100, month - 1, day))
    }

    return date.toISOString().slice(0, 10)
  }
}
