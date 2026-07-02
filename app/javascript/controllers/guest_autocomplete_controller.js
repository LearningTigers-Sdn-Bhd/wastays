import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "guestId", "email", "phone", "country", "gender", "documentType", "governmentId", "dateOfBirth"]
  static values = { url: String }

  connect() {
    this.searchRequestId = 0
    this.hideResults()
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) {
      this.hideResults()
      return
    }

    const requestId = ++this.searchRequestId

    fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
      .then(response => response.json())
      .then(data => {
        if (requestId !== this.searchRequestId) return
        this.renderResults(data)
      })
      .catch(() => {
        if (requestId !== this.searchRequestId) return
        this.hideResults()
      })
  }

  renderResults(guests) {
    if (guests.length === 0) {
      this.hideResults()
      return
    }

    this.resultsTarget.replaceChildren(...guests.map((guest) => this.buildResult(guest)))

    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  buildResult(guest) {
    const result = document.createElement("div")
    result.className = "p-3 hover:bg-slate-50 cursor-pointer border-b border-slate-100 last:border-0"
    result.setAttribute("role", "option")
    result.dataset.action = "click->guest-autocomplete#select"
    result.dataset.guestId = guest.id
    result.dataset.guestName = guest.name
    result.dataset.guestEmail = guest.email || ""
    result.dataset.guestPhone = guest.phone || ""
    result.dataset.guestCountry = guest.country || ""
    result.dataset.guestGender = guest.gender || ""
    result.dataset.guestDocumentType = guest.document_type || ""
    result.dataset.guestGovernmentId = guest.government_id || ""
    result.dataset.guestDateOfBirth = guest.date_of_birth || ""

    const name = document.createElement("div")
    name.className = "font-bold text-slate-900"
    name.textContent = guest.name

    const contact = document.createElement("div")
    contact.className = "text-xs text-slate-500"
    contact.textContent = [guest.email, guest.phone].filter(Boolean).join(" • ")

    result.append(name, contact)
    return result
  }

  select(event) {
    clearTimeout(this.hideTimeout)

    const el = event.currentTarget
    this.inputTarget.value = el.dataset.guestName
    this.guestIdTarget.value = el.dataset.guestId
    
    if (this.hasEmailTarget) this.emailTarget.value = el.dataset.guestEmail
    if (this.hasPhoneTarget) this.phoneTarget.value = el.dataset.guestPhone
    if (this.hasCountryTarget) this.countryTarget.value = el.dataset.guestCountry
    if (this.hasGenderTarget) this.genderTarget.value = el.dataset.guestGender
    if (this.hasDocumentTypeTarget) this.documentTypeTarget.value = el.dataset.guestDocumentType
    if (this.hasGovernmentIdTarget) this.governmentIdTarget.value = el.dataset.guestGovernmentId
    if (this.hasDateOfBirthTarget) this.dateOfBirthTarget.value = el.dataset.guestDateOfBirth

    this.element.dispatchEvent(new CustomEvent("guest:selected", {
      bubbles: true,
      detail: {
        guest: {
          id: el.dataset.guestId,
          name: el.dataset.guestName,
          email: el.dataset.guestEmail,
          phone: el.dataset.guestPhone,
          country: el.dataset.guestCountry,
          gender: el.dataset.guestGender,
          document_type: el.dataset.guestDocumentType,
          government_id: el.dataset.guestGovernmentId,
          date_of_birth: el.dataset.guestDateOfBirth
        }
      }
    }))

    this.hideResults()
  }

  hideOnBlur() {
    this.hideTimeout = setTimeout(() => {
      this.hideResults()
    }, 150)
  }

  hideResults() {
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  // Clear guest ID if user changes name manually
  clearGuestId() {
    this.guestIdTarget.value = ""
  }
}
