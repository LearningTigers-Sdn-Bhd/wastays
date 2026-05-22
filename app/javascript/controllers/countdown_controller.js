import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    expiry: String
  }

  connect() {
    this.expiryTime = new Date(this.expiryValue).getTime()
    this.update()
    this.timer = setInterval(() => this.update(), 1000)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  update() {
    const now = new Date().getTime()
    const distance = this.expiryTime - now

    if (distance < 0) {
      clearInterval(this.timer)
      this.element.innerHTML = "Expired"
      window.location.reload()
      return
    }

    const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60))
    const seconds = Math.floor((distance % (1000 * 60)) / 1000)

    this.element.innerHTML = `${minutes}m ${seconds}s`
  }
}
