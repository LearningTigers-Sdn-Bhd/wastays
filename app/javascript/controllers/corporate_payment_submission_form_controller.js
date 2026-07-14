import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["invoice", "amount", "currency"]

  sync() {
    const option = this.invoiceTarget.selectedOptions[0]
    if (!option || !option.dataset.outstanding) return

    this.amountTarget.value = option.dataset.outstanding
    this.currencyTarget.value = option.dataset.currency
  }
}
