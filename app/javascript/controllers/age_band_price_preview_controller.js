import { Controller } from "@hotwired/stimulus"

// Scoped to the whole Age Bands section (not per-row) so every row's preview
// can react to a single "preview using this room type" selector. Rows are
// found by data-role rather than named Stimulus targets so newly cloned
// "+ Add Band" rows (plain innerHTML, no controller of their own) work
// without any extra wiring.
export default class extends Controller {
  static targets = ["roomTypeSelect"]
  static values = { currency: String }

  connect() {
    this.update()
  }

  update() {
    const anchorPrice = this.currentAnchorPrice()

    this.element.querySelectorAll('[data-role="age-band-row"]').forEach((row) => {
      this.updateRow(row, anchorPrice)
    })
  }

  currentAnchorPrice() {
    if (!this.hasRoomTypeSelectTarget) return null

    const option = this.roomTypeSelectTarget.selectedOptions[0]
    if (!option) return null

    const price = parseFloat(option.dataset.basePrice)
    return Number.isNaN(price) ? null : price
  }

  updateRow(row, anchorPrice) {
    const modeSelect = row.querySelector('[data-role="pricing-mode"]')
    const valueInput = row.querySelector('[data-role="price-value"]')
    const preview = row.querySelector('[data-role="price-preview"]')
    if (!modeSelect || !valueInput || !preview) return

    const value = parseFloat(valueInput.value)
    if (Number.isNaN(value)) {
      preview.textContent = ""
      return
    }

    if (modeSelect.value === "amount") {
      preview.textContent = `= ${this.currencyValue} ${value.toFixed(2)} per night (flat, regardless of room rate)`
      return
    }

    if (anchorPrice === null) {
      preview.textContent = `= ${(value * 100).toFixed(0)}% of the room's Standard Rate`
      return
    }

    const amount = (value * anchorPrice).toFixed(2)
    preview.textContent = `= ${this.currencyValue} ${amount} (${(value * 100).toFixed(0)}% of ${this.currencyValue} ${anchorPrice.toFixed(2)}/night)`
  }
}
