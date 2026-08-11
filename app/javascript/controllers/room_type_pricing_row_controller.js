import { Controller } from "@hotwired/stimulus"

// Scoped per room-type row in the rate plan form: shows the pricing value
// input only when this row's own mode select is set to a derived mode, and
// live-previews the resulting price against that room's own Standard Rate.
//
// The mode is a PanelsUI::SelectMenu, which keeps a real <select> as its source
// of truth and re-dispatches input/change from it, so the row is read through
// that native element rather than a Stimulus target on the styled wrapper.
export default class extends Controller {
  static targets = [ "value", "occupancy", "preview" ]
  static values = { anchorPrice: Number, currency: String, perPerson: Boolean }

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  update() {
    const mode = this.modeSelect?.value
    if (!mode) return

    if (!this.hasPreviewTarget) return

    const value = parseFloat(this.valueInput?.value)

    if (this.perPersonValue) {
      this.valueTarget.classList.toggle("hidden", mode === "fixed")
      if (this.hasOccupancyTarget) this.occupancyTarget.classList.toggle("hidden", mode !== "fixed")
    }

    if (mode === "fixed") {
      if (this.perPersonValue) {
        this.previewTarget.textContent = "These are the normal nightly prices; override individual dates under Rates & Availability"
        return
      }
      this.valueInput.min = "0"
      this.valueInput.placeholder = this.anchorPriceValue.toFixed(2)
      this.previewTarget.textContent = Number.isNaN(value)
        ? "Enter the starting nightly price"
        : `Starts at ${this.currencyValue} ${value.toFixed(2)}/night; change individual dates under Rates & Availability`
      return
    }

    this.valueInput.removeAttribute("min")
    this.valueInput.placeholder = mode === "offset" ? "-10.00" : "-10"
    if (Number.isNaN(value)) {
      this.previewTarget.textContent = ""
      return
    }

    const anchor = this.anchorPriceValue
    let result = mode === "offset" ? anchor + value : anchor * (1 + value / 100)
    result = Math.max(result, 0)

    const changeLabel = mode === "offset"
      ? `${value >= 0 ? "+" : ""}${this.currencyValue} ${value.toFixed(2)}`
      : `${value >= 0 ? "+" : ""}${value.toFixed(0)}%`

    this.previewTarget.textContent = `= ${this.currencyValue} ${result.toFixed(2)} (${changeLabel} of ${this.currencyValue} ${anchor.toFixed(2)}/night)`
  }

  get modeSelect() {
    return this.element.querySelector('[data-role="pricing-mode"] select')
  }

  get valueInput() {
    return this.valueTarget.querySelector("input")
  }
}
