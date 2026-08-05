import { Controller } from "@hotwired/stimulus"

// Scoped per room-type row in the rate plan form: shows the pricing value
// input only when this row's own mode select is set to a derived mode, and
// live-previews the resulting price against that room's own Standard Rate.
//
// The mode is a PanelsUI::SelectMenu, which keeps a real <select> as its source
// of truth and re-dispatches input/change from it, so the row is read through
// that native element rather than a Stimulus target on the styled wrapper.
export default class extends Controller {
  static targets = [ "value", "preview" ]
  static values = { anchorPrice: Number, currency: String }

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  update() {
    const mode = this.modeSelect?.value
    if (!mode) return

    this.valueTarget.classList.toggle("hidden", mode === "fixed")

    if (!this.hasPreviewTarget) return

    if (mode === "fixed") {
      this.previewTarget.textContent = ""
      return
    }

    const value = parseFloat(this.valueInput?.value)
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
