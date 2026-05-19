import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "guestId", "intent", "name", "email", "phone", "country", "gender", "documentType", "governmentId", "modal"
  ]

  connect() {
    this.confirmed = false
    this.originalGuest = null

    // Initialize originalGuest if a guest is already selected (e.g. after validation error)
    if (this.hasGuestIdTarget && this.guestIdTarget.value) {
      this.originalGuest = this.currentGuest()
    }
  }

  storeOriginalGuest(event) {
    this.originalGuest = this.normalizedGuest(event.detail.guest)
    this.intentTarget.value = ""
    this.confirmed = false
  }

  confirm(event) {
    if (this.confirmed) return

    if (!this.hasGuestIdTarget || !this.guestIdTarget.value || !this.originalGuest || !this.changed()) return

    event.preventDefault()
    
    // Ensure we have the form reference
    this.form = event.target.tagName === "FORM" ? event.target : event.target.closest("form") || this.element.querySelector("form")

    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      this.modalTarget.classList.add("flex")
    }
  }

  chooseIntent(event) {
    const button = event.currentTarget
    const intent = button.dataset.intent
    const buttons = this.modalTarget.querySelectorAll("button")
    
    // Visual feedback on the button
    const originalContent = button.innerHTML
    buttons.forEach((modalButton) => { modalButton.disabled = true })
    button.innerHTML = `
      <div class="flex items-center gap-2">
        <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span>Processing...</span>
      </div>
    `
    
    // Keep modal visible for a split second so they see the loading state
    setTimeout(() => {
      this.hideModal()
      this.submitWithIntent(intent)
      
      // Reset button state for if they come back
      setTimeout(() => {
        buttons.forEach((modalButton) => { modalButton.disabled = false })
        button.innerHTML = originalContent
      }, 500)
    }, 300)
  }

  cancel() {
    this.hideModal()
  }

  hideModal() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      this.modalTarget.classList.remove("flex")
    }
  }

  submitWithIntent(intent) {
    this.intentTarget.value = intent
    
    const form = this.form || this.element.querySelector("form")
    if (!form) return

    // Find the submit button associated with this form
    let submitButton = form.querySelector('button[type="submit"]')
    if (!submitButton && form.id) {
      submitButton = document.querySelector(`button[type="submit"][form="${form.id}"]`)
    }

    try {
      this.confirmed = true
      if (submitButton) {
        form.requestSubmit(submitButton)
      } else {
        form.requestSubmit()
      }
    } catch (error) {
      form.submit()
    } finally {
      // Reset confirmed flag after the synchronous part of submission is done.
      // This allows the user to try again if the submission fails (e.g. 422 error).
      this.confirmed = false
    }
  }

  changed() {
    const current = this.currentGuest()
    const original = this.originalGuest
    return Object.entries(current).some(([key, value]) => value !== (original[key] || ""))
  }

  currentGuest() {
    return this.normalizedGuest({
      name: this.nameTarget.value,
      email: this.emailTarget.value,
      phone: this.phoneTarget.value,
      country: this.countryTarget.value,
      gender: this.genderTarget.value,
      document_type: this.documentTypeTarget.value,
      government_id: this.governmentIdTarget.value
    })
  }

  normalizedGuest(guest) {
    return {
      name: this.normalize(guest.name),
      email: this.normalize(guest.email).toLowerCase(),
      phone: this.normalize(guest.phone),
      country: this.normalize(guest.country),
      gender: this.normalize(guest.gender).toLowerCase(),
      document_type: this.normalize(guest.document_type).toLowerCase(),
      government_id: this.normalize(guest.government_id).toLowerCase()
    }
  }

  normalize(value) {
    return (value || "").trim()
  }

}
