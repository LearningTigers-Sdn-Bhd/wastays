import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "emailInput", "lookupButton", "feedback", "detailsPanel", "field",
    "countryInput", "countryMenu", "documentSelect", "documentInput", "documentLabel", "documentField"
  ]
  static values = {
    lookupUrl: String,
    countries: Array
  }

  initialize() {
    this.documentManuallySet = false
    this.detailsUnlocked = false
    this.lookupInProgress = false
    this.lastLookupEmail = ""
  }

  connect() {
    this.updateEnabled()
    this.updateLabel()
    this.setDetailsUnlocked(false)

    if (this.emailInputTarget.value) {
      this.lookup()
    }
  }

  // Actions
  handleEmailInput() {
    const email = this.normalizedEmail()
    if (email !== this.lastLookupEmail) {
      this.setDetailsUnlocked(false)
      this.setFeedback("Enter your email first. We will auto-fill your details if we find a previous booking.")
    }
  }

  handleEmailKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.lookup()
    }
  }

  lookup() {
    const email = this.normalizedEmail()
    if (!email || !this.lookupUrlValue || this.lookupInProgress) return

    this.lookupInProgress = true
    if (this.hasLookupButtonTarget) this.lookupButtonTarget.disabled = true
    this.setFeedback("Checking your email...")

    fetch(`${this.lookupUrlValue}?email=${encodeURIComponent(email)}`, {
      headers: { "Accept": "application/json" }
    })
      .then(response => response.json())
      .then(payload => {
        this.lastLookupEmail = email

        if (payload.corporate_valid === false) {
          this.setDetailsUnlocked(false)
          this.setFeedback(payload.corporate_message, "error")
          return
        }

        if (payload.restriction_failed) {
          this.setDetailsUnlocked(false)
          this.setFeedback(payload.message, "error")
          return
        }

        this.setDetailsUnlocked(true)

        if (payload.found) {
          this.applyGuestDetails(payload.guest_details || {})
          const msg = payload.corporate_message 
            ? `${payload.corporate_message} Welcome back!`
            : "Welcome back! We found your saved details."
          this.setFeedback(msg, "success")
        } else {
          this.clearGuestFields()
          this.setFeedback(payload.corporate_message || "New email detected. Please fill in your details below.", payload.corporate_message ? "success" : "")
        }
      })
      .catch(() => {
        this.setDetailsUnlocked(true)
        this.clearGuestFields()
        this.setFeedback("Unable to check email right now. Please fill in your details manually.", "error")
      })
      .finally(() => {
        this.lookupInProgress = false
        if (this.hasLookupButtonTarget) this.lookupButtonTarget.disabled = false
        this.updateEnabled()
        this.autoSelectDocumentType()
      })
  }

  handleCountryInput(event) {
    this.renderCountryOptions(event.target.value)
    this.updateEnabled()
    this.autoSelectDocumentType()
  }

  handleCountryFocus() {
    this.renderCountryOptions(this.countryInputTarget.value)
  }

  handleCountryBlur() {
    setTimeout(() => this.closeCountryMenu(), 120)
  }

  selectCountry(event) {
    const option = event.target.closest("[data-country-option]")
    if (!option) return
    
    // Prevent blur from closing menu before selection
    if (event.type === "mousedown") event.preventDefault()

    this.countryInputTarget.value = option.dataset.countryOption || ""
    this.closeCountryMenu()
    this.updateEnabled()
    this.autoSelectDocumentType()
  }

  handleDocumentChange() {
    this.documentManuallySet = true
    this.updateEnabled()
    this.updateLabel()
  }

  // Internal Helpers
  normalizedEmail() {
    return this.emailInputTarget.value?.trim().toLowerCase() || ""
  }

  setFeedback(message, tone = "neutral") {
    if (!this.hasFeedbackTarget) return
    this.feedbackTarget.textContent = message
    this.feedbackTarget.classList.remove("text-neutral-text-secondary", "text-status-success", "text-status-error")
    if (tone === "success") {
      this.feedbackTarget.classList.add("text-status-success")
    } else if (tone === "error") {
      this.feedbackTarget.classList.add("text-status-error")
    } else {
      this.feedbackTarget.classList.add("text-neutral-text-secondary")
    }
  }

  setDetailsUnlocked(unlocked) {
    this.detailsUnlocked = unlocked
    if (this.hasDetailsPanelTarget) {
      this.detailsPanelTarget.classList.toggle("opacity-60", !unlocked)
      this.detailsPanelTarget.classList.toggle("pointer-events-none", !unlocked)
    }
    this.fieldTargets.forEach((field) => {
      field.disabled = !unlocked
    })
    if (!unlocked) {
      this.closeCountryMenu()
      if (this.hasDocumentFieldTarget) this.documentFieldTarget.classList.add("hidden")
    }
    this.updateEnabled()

    const submitBtn = this.element.querySelector('[type="submit"]')
    if (submitBtn) {
      const paymentReady = this.element.getAttribute("data-checkout-payment-ready-value") !== "false"
      submitBtn.disabled = !unlocked || !paymentReady
    }
  }

  clearGuestFields() {
    this.fieldTargets.forEach((field) => {
      field.value = ""
    })
    this.documentManuallySet = false
    this.updateLabel()
  }

  applyGuestDetails(guestDetails) {
    this.fieldTargets.forEach((field) => {
      const key = field.dataset.guestField
      if (!key || !Object.prototype.hasOwnProperty.call(guestDetails, key)) return
      field.value = guestDetails[key] || ""
    })
    this.documentManuallySet = !!this.documentSelectTarget.value
    this.updateLabel()
  }

  updateEnabled() {
    if (!this.detailsUnlocked) {
      this.documentSelectTarget.disabled = true
      this.documentInputTarget.disabled = true
      this.documentFieldTarget.classList.add("hidden")
      return
    }

    const hasCountry = this.countryInputTarget.value.trim().length > 0
    this.documentSelectTarget.disabled = !hasCountry
    
    if (!hasCountry) {
      this.documentSelectTarget.value = ""
      this.documentManuallySet = false
    }

    const hasDocumentType = hasCountry && this.documentSelectTarget.value
    this.documentInputTarget.disabled = !hasDocumentType
    this.documentFieldTarget.classList.toggle("hidden", !hasDocumentType)
  }

  autoSelectDocumentType() {
    const country = this.countryInputTarget.value.trim().toLowerCase()
    if (!country) return
    if (this.documentManuallySet && this.documentSelectTarget.value) return

    const isMalaysia = ["malaysia", "my", "mys"].includes(country)
    this.documentSelectTarget.value = isMalaysia ? "ic" : "passport"
    this.updateLabel()
    this.updateEnabled()
  }

  updateLabel() {
    if (!this.documentSelectTarget.value) {
      this.documentLabelTarget.textContent = "IC / Passport Number"
      return
    }
    const label = this.documentSelectTarget.value === "ic" ? "IC Number" : "Passport Number"
    this.documentLabelTarget.textContent = label
  }

  renderCountryOptions(query) {
    const normalized = query.trim().toLowerCase()
    const matches = normalized
      ? this.countriesValue.filter((country) => country.toLowerCase().includes(normalized))
      : this.countriesValue
    
    const limited = matches.slice(0, 12)
    this.countryMenuTarget.innerHTML = limited
      .map((country) => `<button type="button" class="w-full px-3 py-2 text-left text-sm text-neutral-text-primary hover:bg-neutral-100" data-country-option="${country}">${country}</button>`)
      .join("")
    
    this.countryMenuTarget.classList.toggle("hidden", limited.length === 0)
  }

  closeCountryMenu() {
    if (this.hasCountryMenuTarget) this.countryMenuTarget.classList.add("hidden")
  }
}
