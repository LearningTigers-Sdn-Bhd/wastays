import { Controller } from "@hotwired/stimulus"
import { renderStayDiscountExample, stayDiscountExample } from "lib/stay_discount_example"

// Guided "Add discount" flow: one question per step instead of the full
// four-field row at once. Only used for creating a *new* discount — editing
// an existing row keeps the compact form (stay_discount_example_controller).
// On the final step, it lets nested-rows#add clone a real row exactly as
// before, then fills that row's fields in and dispatches input/change so its
// own stay-discount-example controller renders the same worked example.
export default class extends Controller {
  static targets = [
    "startButton", "card", "step", "stepLabel",
    "minNights", "discountType", "value", "unit", "simulateNights", "fromNightMode", "fromNightValue",
    "heading", "body", "reviewText",
    "back", "continueButton", "confirmButton",
    "rowsList"
  ]
  static values = { step: { type: Number, default: 1 }, price: Number, currency: String, perPerson: Boolean }

  start() {
    this.reset()
    this.cardTarget.classList.remove("hidden")
    this.startButtonTarget.classList.add("hidden")
    this.stepValue = 1
  }

  cancel() {
    this.cardTarget.classList.add("hidden")
    this.startButtonTarget.classList.remove("hidden")
  }

  reset() {
    this.minNightsTarget.value = ""
    this.valueTarget.value = ""
    this.simulateNightsTarget.value = ""
    this.fromNightValueTarget.value = ""
    this.discountTypeTargets.forEach((input) => { input.checked = input.value === "percent" })
    this.fromNightModeTargets.forEach((input) => { input.checked = input.value === "every" })
    this.unitTarget.textContent = "%"
  }

  back() {
    this.stepValue = Math.max(1, this.stepValue - 1)
  }

  continue() {
    this.stepValue = Math.min(5, this.stepValue + 1)
  }

  selectDiscountType(event) {
    this.unitTarget.textContent = event.target.value === "amount" ? this.currencyValue : "%"
    this.updateExample()
    this.stepValue = 3
  }

  selectFromNightMode() {
    this.updateExample()
  }

  simulate() {
    this.updateExample()
  }

  stepValueChanged() {
    this.stepTargets.forEach((step) => {
      step.classList.toggle("hidden", Number(step.dataset.wizardStep) !== this.stepValue)
    })
    if (this.hasBackTarget) this.backTarget.classList.toggle("invisible", this.stepValue <= 1)
    if (this.hasContinueButtonTarget) this.continueButtonTarget.classList.toggle("hidden", this.stepValue >= 5)
    if (this.hasConfirmButtonTarget) this.confirmButtonTarget.classList.toggle("hidden", this.stepValue < 5)
    if (this.hasStepLabelTarget) this.stepLabelTarget.textContent = `Step ${this.stepValue} of 5`
    if (this.stepValue === 5) this.updateReview()
  }

  get minNights() {
    return Number.parseInt(this.minNightsTarget.value, 10)
  }

  get percent() {
    return !this.discountTypeTargets.find((input) => input.checked) || this.discountTypeTargets.find((input) => input.checked).value !== "amount"
  }

  get discountValue() {
    return Number.parseFloat(this.valueTarget.value)
  }

  get fromNight() {
    const mode = this.fromNightModeTargets.find((input) => input.checked)?.value || "every"
    if (mode === "every") return 1
    return Number.parseInt(this.fromNightValueTarget.value, 10) || 1
  }

  // Fired by the Pricing tab as its price is edited, so the simulator and the
  // rows' examples follow what is on screen rather than the last saved price.
  updatePrice(event) {
    this.priceValue = event.detail.price
    if (this.hasSimulateNightsTarget) this.updateExample()
  }

  updateExample() {
    const nights = Number.parseInt(this.simulateNightsTarget.value, 10) || this.minNights

    const example = stayDiscountExample({
      nights,
      percent: this.percent,
      value: this.discountValue,
      fromNight: this.fromNight,
      price: this.priceValue,
      currency: this.currencyValue,
      perPerson: this.perPersonValue
    })

    renderStayDiscountExample(example, { heading: this.headingTarget, body: this.bodyTarget })
  }

  updateReview() {
    const type = this.percent ? `${this.valueTarget.value || "?"}%` : `${this.currencyValue} ${this.valueTarget.value || "?"}`
    const from = this.fromNight > 1 ? `from night ${this.fromNight} onward` : "every night"
    this.reviewTextTarget.textContent = `Guests staying ${this.minNights || "?"}+ nights get ${type} off, ${from}.`
  }

  // nested-rows#add (bound alongside this action on the same button) has
  // already cloned a fresh row into rowsListTarget by the time this runs.
  applyAnswers() {
    const row = this.rowsListTarget.lastElementChild
    if (!row) return

    this.setField(row, "minNights", this.minNightsTarget.value)
    this.setField(row, "discountType", this.percent ? "percent" : "amount")
    this.setField(row, "value", this.valueTarget.value)
    this.setField(row, "fromNight", this.fromNight)

    this.cancel()
  }

  setField(row, target, value) {
    const field = row.querySelector(`[data-stay-discount-example-target="${target}"]`)
    if (!field) return
    field.value = value
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
