import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folioType", "payerType", "lockedPayer"]

  connect() {
    this.sync()
  }

  sync() {
    const lockedPayer = this.lockedPayerFor(this.folioTypeTarget.value)

    if (lockedPayer) {
      this.payerTypeTarget.value = lockedPayer
      this.payerTypeTarget.disabled = true
      this.lockedPayerTarget.value = lockedPayer
      this.lockedPayerTarget.disabled = false
    } else {
      this.payerTypeTarget.disabled = false
      this.lockedPayerTarget.disabled = true
      if (!this.payerTypeTarget.value) this.payerTypeTarget.value = "company"
    }
  }

  lockedPayerFor(folioType) {
    if (folioType === "guest") return "guest"
    if (folioType === "house") return "hotel"

    return null
  }
}
