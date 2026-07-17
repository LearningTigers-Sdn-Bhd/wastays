import { Controller } from "@hotwired/stimulus"
import { applyBounds, formatRange } from "controllers/panels_ui/support/cally_calendar"
import { connectCalendarControls, disconnectCalendarControls, syncCaption, toggleCaption, selectCaption, onCaptionTriggerKeydown, onCaptionListboxKeydown, closeCaptions } from "controllers/panels_ui/support/calendar_controls"

// Identifier: panels-ui--date-picker
//
// A hidden <input> (ISO form source of truth) plus a themed button (the popover
// trigger) that displays the value and opens a nested PanelsUI::Popover holding a
// Cally calendar. Cally writes the chosen ISO date into the hidden input and updates
// the display; the popover closes on selection via its outlet.
export default class extends Controller {
  static targets = ["input", "calendar", "display", "months", "caption", "monthButton", "monthLabel", "monthListbox", "yearButton", "yearLabel", "yearListbox"]
  static outlets = ["panels-ui--popover"]
  static values = {
    mode: { type: String, default: "single" }, // single | range
    dateFormat: String,
    min: String,
    max: String,
    linkedTo: String,
    months: { type: Number, default: 1 },
    responsiveMonths: { type: Boolean, default: true }
  }

  connect() {
    if (!this.hasCalendarTarget) return

    applyBounds(this.calendarTarget, { min: this.boundOrNull("min"), max: this.boundOrNull("max") })
    const iso = this.inputTarget.value.trim()
    this.calendarTarget.value = this.calendarValue(iso)
    this.renderDisplay(iso)
    // Apply the linked-range constraint to any value already present on load.
    if (this.hasLinkedToValue) this.syncLinkedMin(this.startISO(iso))
    this.onFormReset = () => requestAnimationFrame(() => this.resetFromInput())
    this.inputTarget.form?.addEventListener("reset", this.onFormReset)
    connectCalendarControls(this)
    this.element.dataset.enhanced = "true"
  }

  disconnect() {
    disconnectCalendarControls(this)
    this.inputTarget.form?.removeEventListener("reset", this.onFormReset)
    delete this.element.dataset.enhanced
  }

  onCalendarFocusday(event) { syncCaption(this, event.detail?.toISOString?.().slice(0, 10)) }
  toggleCaption(event) { toggleCaption(this, event) }
  selectCaption(event) { selectCaption(this, event) }
  onCaptionTriggerKeydown(event) { onCaptionTriggerKeydown(this, event) }
  onCaptionListboxKeydown(event) { onCaptionListboxKeydown(this, event) }
  closeCaptions() { closeCaptions(this) }

  resetFromInput() {
    const iso = this.inputTarget.value.trim()
    this.calendarTarget.value = this.calendarValue(iso)
    this.renderDisplay(iso)
    if (this.hasLinkedToValue) this.syncLinkedMin(this.startISO(iso))
  }

  onCalendarChange(event) {
    const value = event.target.value
    if (!value) {
      if (!this.isRange && this.hasLinkedToValue) {
        this.inputTarget.value = ""
        this.renderDisplay("")
        this.syncLinkedMin("")
        this.emitInput()
      }
      return
    }

    this.inputTarget.value = value // Cally emits ISO ("YYYY-MM-DD" or "start/end").
    this.renderDisplay(value)
    if (!this.isRange && this.hasLinkedToValue) this.syncLinkedMin(value)
    this.emitInput()

    // Single picks are done in one click; a range is done once both ends are set.
    if (!this.isRange || this.rangeComplete(value)) this.closePopover()
  }

  // Show the formatted value in the trigger, or clear it so the placeholder shows.
  renderDisplay(iso) {
    if (!this.hasDisplayTarget) return
    this.displayTarget.textContent = iso ? (this.isRange ? formatRange(iso) : iso) : ""
  }

  get isRange() {
    return this.modeValue === "range"
  }

  rangeComplete(value) {
    const [start, end] = value.split("/")
    return Boolean(start && end)
  }

  // The hidden input stores exactly Cally's value format ("YYYY-MM-DD" or
  // "start/end"), so seeding the calendar is a direct assignment.
  calendarValue(iso) {
    return iso
  }

  startISO(iso) {
    return (iso || "").split("/")[0]
  }

  syncLinkedMin(startDate) {
    if (!this.hasLinkedToValue) return

    const endEl = document.getElementById(this.linkedToValue)
    const endPicker = endEl?.closest(".panel-date-picker")
    const endCalendar = endPicker?.querySelector("[data-panels-ui--date-picker-target='calendar']")
    if (!endCalendar) return

    endCalendar.min = startDate || ""
    if (!startDate || !endEl.value || endEl.value >= startDate) return

    endEl.value = ""
    endCalendar.value = ""
    const display = endPicker.querySelector("[data-panels-ui--date-picker-target='display']")
    if (display) display.textContent = ""
    endEl.dispatchEvent(new Event("input", { bubbles: true }))
    endEl.dispatchEvent(new Event("change", { bubbles: true }))
  }

  closePopover() {
    if (this.hasPanelsUiPopoverOutlet) this.panelsUiPopoverOutlet.close()
  }

  emitInput() {
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  boundOrNull(name) {
    const has = name === "min" ? this.hasMinValue : this.hasMaxValue
    return has ? (name === "min" ? this.minValue : this.maxValue) : null
  }
}
