import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { bookingId: String }

  connect() {
    if (sessionStorage.getItem(`checkout_success_closed_${this.bookingIdValue}`)) {
      this.element.remove()
      this.cleanUrl()
      return
    }
    this.element.showModal()
  }

  dismiss() {
    sessionStorage.setItem(`checkout_success_closed_${this.bookingIdValue}`, "true")
    this.element.close()
    this.cleanUrl()
  }

  cleanUrl() {
    const url = new URL(window.location)
    url.searchParams.delete("checkout_success")
    history.replaceState({}, "", url)
  }
}
