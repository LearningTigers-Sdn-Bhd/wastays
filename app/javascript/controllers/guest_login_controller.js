import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "whatsapp", "email", "emailSuccess"]

  connect() {
    const params = new URLSearchParams(window.location.search)
    if (params.get("email_sent") === "true") this.showEmailSuccess()
  }

  showWhatsapp() {
    this.choiceTarget.classList.add("hidden")
    this.whatsappTarget.classList.remove("hidden")
  }

  showEmail() {
    this.choiceTarget.classList.add("hidden")
    this.emailTarget.classList.remove("hidden")
  }

  showEmailSuccess() {
    this.choiceTarget.classList.add("hidden")
    this.emailTarget.classList.add("hidden")
    this.emailSuccessTarget.classList.remove("hidden")
  }

  back() {
    this.choiceTarget.classList.remove("hidden")
    this.whatsappTarget.classList.add("hidden")
    this.emailTarget.classList.add("hidden")
    this.emailSuccessTarget.classList.add("hidden")
  }
}
