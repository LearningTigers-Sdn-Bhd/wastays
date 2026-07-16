import { Controller } from "@hotwired/stimulus"
import { createTimeControl } from "controllers/panels_ui/support/time_control"

export default class extends Controller {
  static targets = ["input", "display", "timeControl"]
  static outlets = ["panels-ui--popover"]
  static values = {
    min: String, max: String,
    step: { type: Number, default: 1 },
    minuteStep: { type: Number, default: 1 },
    secondStep: { type: Number, default: 1 },
    hourCycle: { type: Number, default: 24 },
    precision: { type: String, default: "minutes" }
  }

  connect() {
    if (!this.hasTimeControlTarget) return
    this.control = createTimeControl({
      root: this.timeControlTarget,
      min: this.hasMinValue ? this.minValue : undefined,
      max: this.hasMaxValue ? this.maxValue : undefined,
      minuteStep: this.minuteStepValue || this.stepValue,
      secondStep: this.secondStepValue,
      onChange: (value) => this.write(value),
      onEnter: () => this.closePopover()
    })
    this.control.setValue(this.inputTarget.value)
    this.renderDisplay(this.inputTarget.value)
    this.onFormReset = () => requestAnimationFrame(() => {
      this.control.setValue(this.inputTarget.value)
      this.renderDisplay(this.inputTarget.value)
    })
    this.inputTarget.form?.addEventListener("reset", this.onFormReset)
    this.onPopoverOpen = () => requestAnimationFrame(() => this.control.scrollSelected())
    this.element.addEventListener("panels-ui:popover-open", this.onPopoverOpen)
    this.element.dataset.enhanced = "true"
  }

  disconnect() {
    this.control?.destroy()
    this.inputTarget.form?.removeEventListener("reset", this.onFormReset)
    this.element.removeEventListener("panels-ui:popover-open", this.onPopoverOpen)
    delete this.element.dataset.enhanced
  }

  onTimeKeydown(event) { this.control?.onKeydown(event) }
  onTimeClick(event) { this.control?.onClick(event) }
  onTimeInput(event) { this.control?.onInput(event) }
  onTimeFocusIn(event) { this.control?.onFocusIn(event) }
  onTimeFocusOut(event) { this.control?.onFocusOut(event) }

  write(value) {
    this.inputTarget.value = value
    this.renderDisplay(value)
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  renderDisplay(value) {
    if (this.hasDisplayTarget) this.displayTarget.textContent = value ? this.control.formatValue(value) : ""
  }

  closePopover() { if (this.hasPanelsUiPopoverOutlet) this.panelsUiPopoverOutlet.close(true) }
}
