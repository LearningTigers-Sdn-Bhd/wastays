import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "whatsapp", "email", "emailSuccess"]

  static values = { isError: Boolean }

  connect() {
    const params = new URLSearchParams(window.location.search)
    
    // Add a tiny delay to ensure targets are fully mapped and classes are correctly handled
    requestAnimationFrame(() => {
      if (this.isErrorValue) {
        this.showEmail()
      } else if (params.get("email_sent") === "true") {
        this.showEmailSuccess()
      }
    })
  }

  hideAll() {
    this.choiceTarget.classList.add("hidden")
    this.whatsappTarget.classList.add("hidden")
    this.emailTarget.classList.add("hidden")
    this.emailSuccessTarget.classList.add("hidden")
  }

  showWhatsapp() {
    this.hideAll()
    this.whatsappTarget.classList.remove("hidden")
  }

  showEmail() {
    this.hideAll()
    this.emailTarget.classList.remove("hidden")
  }

  showEmailSuccess() {
    this.hideAll()
    this.emailSuccessTarget.classList.remove("hidden")
  }

  back() {
    this.hideAll()
    this.choiceTarget.classList.remove("hidden")
    
    // Clear URL params without reloading to prevent re-showing success on back/refresh
    const url = new URL(window.location)
    url.searchParams.delete("email_sent")
    window.history.replaceState({}, document.title, url)
  }
}
