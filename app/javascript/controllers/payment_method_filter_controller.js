import { Controller } from "@hotwired/stimulus"

// Narrows the payment-method list to the methods that are actually eligible:
// by purpose (guest_advance for reservations, direct for walk-in / backdated,
// mirroring PaymentMethods::Eligibility) and by the selected type. When a quote
// URL is present it also prices the method's surcharge and hands the result to
// the billing summary — this controller renders no money itself.
export default class extends Controller {
  static targets = ["type", "method", "emptyState"]
  static values = {
    options: Array,
    quoteUrl: String,
    purpose: String
  }

  connect() {
    this.baseAmount = 0
    this.onTotalsChanged = this.onTotalsChanged.bind(this)
    this.onModeChanged = this.onModeChanged.bind(this)
    window.addEventListener("booking:totals-changed", this.onTotalsChanged)
    window.addEventListener("booking:mode-changed", this.onModeChanged)
    this.filter()
  }

  disconnect() {
    window.removeEventListener("booking:totals-changed", this.onTotalsChanged)
    window.removeEventListener("booking:mode-changed", this.onModeChanged)
  }

  // No method target at all means the hotel has nothing configured; the view
  // renders a warning in place of the select and there is nothing to narrow.
  filter() {
    if (!this.hasMethodTarget) return

    const type = this.selectedType()
    const purpose = this.purposeValue
    const choices = this.optionsValue.filter((option) => {
      if (purpose && option.purpose && option.purpose !== purpose) return false
      return !type || option.type === type
    })
    const native = this.nativeSelect()
    const selected = choices.some((choice) => String(choice.value) === String(native?.value || ""))
      ? native.value
      : String(choices[0]?.value || "")

    this.replaceMethodOptions(choices, selected)
    this.emptyStateTargets.forEach((target) => target.classList.toggle("hidden", choices.length > 0))
    this.quote()
  }

  onTotalsChanged(event) {
    this.baseAmount = Number(event.detail?.amount || 0)
    this.quote()
  }

  // Booking type drives which eligibility purpose applies, so the list has to be
  // rebuilt — not just re-quoted — when the staff member switches type.
  onModeChanged(event) {
    const purpose = event.detail?.purpose
    if (!purpose || purpose === this.purposeValue) return

    this.purposeValue = purpose
    this.filter()
  }

  quote() {
    if (!this.hasQuoteUrlValue || !this.hasMethodTarget) return

    const baseAmount = this.baseAmount
    const methodId = this.nativeSelect()?.value
    if (!methodId || baseAmount <= 0) return this.publishQuote(0, 0)

    const params = new URLSearchParams({
      hotel_payment_method_id: methodId,
      base_amount: baseAmount.toFixed(2),
      purpose: this.purposeValue || "guest_advance"
    })
    fetch(`${this.quoteUrlValue}?${params}`)
      .then((response) => {
        if (!response.ok) throw new Error("Payment quote unavailable")
        return response.json()
      })
      .then((data) => this.publishQuote(data.surcharge_amount, data.surcharge_tax_total))
      .catch(() => this.publishQuote(0, 0))
  }

  selectedType() {
    return this.typeTarget.querySelector("input[type='radio']:checked")?.value || ""
  }

  nativeSelect() {
    return this.methodTarget.querySelector("select")
  }

  replaceMethodOptions(choices, selected) {
    const host = this.methodTarget.querySelector('[data-controller~="panels-ui--select-menu"]')
    const controller = host && this.application.getControllerForElementAndIdentifier(host, "panels-ui--select-menu")
    if (controller) {
      controller.replaceOptions(choices, selected)
      return
    }

    const native = this.nativeSelect()
    if (!native) return
    native.replaceChildren(...choices.map((choice) => new Option(choice.label, choice.value)))
    native.value = selected
  }

  publishQuote(surcharge, surchargeTax) {
    window.dispatchEvent(new CustomEvent("booking:quote-changed", {
      detail: {
        surcharge: Number(surcharge || 0),
        surchargeTax: Number(surchargeTax || 0)
      }
    }))
  }
}
