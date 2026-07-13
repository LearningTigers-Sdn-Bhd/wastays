import { Controller } from "@hotwired/stimulus"
import { applyBounds } from "controllers/panels_ui/support/cally_calendar"
import { createTimeControl } from "controllers/panels_ui/support/time_control"
import { connectCalendarControls, disconnectCalendarControls, syncCaption, toggleCaption, selectCaption, onCaptionTriggerKeydown, onCaptionListboxKeydown, closeCaptions } from "controllers/panels_ui/support/calendar_controls"

export default class extends Controller {
  static targets = ["input", "calendar", "display", "months", "timeControl", "startTimeControl", "endTimeControl", "timeDisplay", "startTimeDisplay", "endTimeDisplay", "caption", "monthButton", "monthLabel", "monthListbox", "yearButton", "yearLabel", "yearListbox"]
  static outlets = ["panels-ui--popover"]
  static values = {
    min: String, max: String,
    step: { type: Number, default: 1 },
    minuteStep: { type: Number, default: 1 },
    secondStep: { type: Number, default: 1 },
    hourCycle: { type: Number, default: 24 },
    precision: { type: String, default: "minutes" },
    mode: { type: String, default: "single" }, linkedTo: String,
    months: { type: Number, default: 1 }, responsiveMonths: { type: Boolean, default: true }
  }

  connect() {
    if (!this.hasCalendarTarget) return
    Object.assign(this, this.parseInput())
    applyBounds(this.calendarTarget, { min: this.hasMinValue ? this.dateOnly(this.minValue) : null, max: this.hasMaxValue ? this.dateOnly(this.maxValue) : null })
    if (this.date) this.calendarTarget.value = this.isRange ? [this.date, this.endDate].filter(Boolean).join("/") : this.date
    this.connectTimeControls()
    this.renderDisplay()
    this.onFormReset = () => requestAnimationFrame(() => this.resetFromInput())
    this.inputTarget.form?.addEventListener("reset", this.onFormReset)
    this.onPopoverOpen = (event) => requestAnimationFrame(() => {
      const root = event.target.querySelector?.(".panel-time-control")
      this.controls.get(root)?.scrollSelected()
    })
    this.element.addEventListener("panels-ui:popover-open", this.onPopoverOpen)
    connectCalendarControls(this)
    this.element.dataset.enhanced = "true"
  }

  disconnect() {
    this.controls?.forEach((control) => control.destroy())
    this.inputTarget.form?.removeEventListener("reset", this.onFormReset)
    this.element.removeEventListener("panels-ui:popover-open", this.onPopoverOpen)
    disconnectCalendarControls(this)
    delete this.element.dataset.enhanced
  }

  connectTimeControls() {
    this.controls = new Map()
    this.addTimeControl(this.isRange ? this.startTimeControlTarget : this.timeControlTarget, "start")
    if (this.isRange) this.addTimeControl(this.endTimeControlTarget, "end")
  }

  addTimeControl(root, endpoint) {
    const value = endpoint === "end" ? this.endTime : this.time
    const control = createTimeControl({
      root,
      ...this.timeBounds(endpoint === "end" ? this.endDate : this.date, endpoint === "end"),
      minuteStep: this.minuteStepValue || this.stepValue,
      secondStep: this.secondStepValue,
      onChange: (next) => {
        if (endpoint === "end") this.endTime = next
        else this.time = next
        this.sync()
      },
      onEnter: () => this.closeChildPopover(root)
    })
    control.setValue(value)
    this.controls.set(root, control)
  }

  onTimeKeydown(event) { this.controls.get(event.currentTarget)?.onKeydown(event) }
  onTimeClick(event) { this.controls.get(event.currentTarget)?.onClick(event) }
  onTimeInput(event) { this.controls.get(event.currentTarget)?.onInput(event) }
  onTimeFocusIn(event) { this.controls.get(event.currentTarget)?.onFocusIn(event) }
  onTimeFocusOut(event) { this.controls.get(event.currentTarget)?.onFocusOut(event) }

  onCalendarChange(event) {
    const dates = String(event.target.value).split("/")
    this.date = dates[0]
    this.endDate = dates[1] || ""
    if (this.date && !this.time) this.time = this.emptyTime
    if (this.isRange && this.endDate && !this.endTime) this.endTime = this.time || this.emptyTime
    this.reconnectTimeControls()
    this.sync()
  }

  sync() {
    if (!this.date) return
    const start = `${this.date}T${this.time || this.emptyTime}`
    this.inputTarget.value = this.isRange && this.endDate ? `${start}/${this.endDate}T${this.endTime || this.emptyTime}` : start
    this.renderDisplay()
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    if (!this.isRange && this.hasLinkedToValue) this.syncLinkedMin(start)
  }

  renderDisplay() {
    const startTime = this.formatTime(this.time || this.emptyTime)
    const endTime = this.formatTime(this.endTime || this.emptyTime)
    if (this.hasTimeDisplayTarget) this.timeDisplayTarget.textContent = startTime
    if (this.hasStartTimeDisplayTarget) this.startTimeDisplayTarget.textContent = startTime
    if (this.hasEndTimeDisplayTarget) this.endTimeDisplayTarget.textContent = endTime
    if (!this.hasDisplayTarget) return
    if (!this.date) this.displayTarget.textContent = ""
    else if (this.isRange && this.endDate) this.displayTarget.textContent = `${this.date} ${startTime} to ${this.endDate} ${endTime}`
    else this.displayTarget.textContent = `${this.date} ${startTime}`
  }

  parseInput() {
    const [start = "", finish = ""] = this.inputTarget.value.split("/")
    const [date = "", time = ""] = start.split("T")
    const [endDate = "", endTime = ""] = finish.split("T")
    return { date, time: this.normalizeTime(time), endDate, endTime: this.normalizeTime(endTime) }
  }

  resetFromInput() {
    Object.assign(this, this.parseInput())
    this.calendarTarget.value = this.isRange ? [this.date, this.endDate].filter(Boolean).join("/") : this.date
    this.reconnectTimeControls()
    this.renderDisplay()
  }

  reconnectTimeControls() {
    if (!this.element.dataset.enhanced) return
    this.controls?.forEach((control) => control.destroy())
    this.connectTimeControls()
  }

  minValueChanged() {
    if (!this.element.dataset.enhanced) return
    applyBounds(this.calendarTarget, { min: this.hasMinValue ? this.dateOnly(this.minValue) : null, max: this.hasMaxValue ? this.dateOnly(this.maxValue) : null })
    const minimum = this.timeBounds(this.date).min
    if (minimum && this.time && this.time < minimum) this.time = minimum
    this.reconnectTimeControls(); this.sync()
  }

  timeBounds(date, rangeEnd = false) {
    const bounds = {}
    if (date && this.hasMinValue && this.dateOnly(this.minValue) === date) bounds.min = this.normalizeTime(this.minValue.split("T")[1])
    if (date && this.hasMaxValue && this.dateOnly(this.maxValue) === date) bounds.max = this.normalizeTime(this.maxValue.split("T")[1])
    if (rangeEnd && date === this.date && this.time && (!bounds.min || this.time > bounds.min)) bounds.min = this.time
    return bounds
  }

  syncLinkedMin(start) {
    const endInput = document.getElementById(this.linkedToValue)
    const endPicker = endInput?.closest(".panel-date-time-picker")
    if (!endPicker) return
    endPicker.setAttribute("data-panels-ui--date-time-picker-min-value", start)
    const calendar = endPicker.querySelector("[data-panels-ui--date-time-picker-target='calendar']")
    if (calendar) calendar.min = this.dateOnly(start)
  }

  closeChildPopover(root) {
    const popoverRoot = root.closest("[data-controller~='panels-ui--popover']")
    this.application.getControllerForElementAndIdentifier(popoverRoot, "panels-ui--popover")?.close(true)
  }

  get isRange() { return this.modeValue === "range" }
  get emptyTime() { return this.precisionValue === "seconds" ? "00:00:00" : "00:00" }
  normalizeTime(value) { return String(value || "").slice(0, this.precisionValue === "seconds" ? 8 : 5) }
  dateOnly(value) { return String(value || "").split("T")[0] }
  formatTime(value) {
    const control = this.controls?.values()?.next()?.value
    return control ? control.formatValue(value) : value
  }

  onCalendarFocusday(event) { syncCaption(this, event.detail?.toISOString?.().slice(0, 10)) }
  toggleCaption(event) { toggleCaption(this, event) }
  selectCaption(event) { selectCaption(this, event) }
  onCaptionTriggerKeydown(event) { onCaptionTriggerKeydown(this, event) }
  onCaptionListboxKeydown(event) { onCaptionListboxKeydown(this, event) }
  closeCaptions() { closeCaptions(this) }
}
