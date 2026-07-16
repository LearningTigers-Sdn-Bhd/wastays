import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const select = this.element.querySelector('select[name="date_preset"]')
    if (select) this.updateCustomControls(select.value === "custom")
  }

  toggleCustom(event) {
    const select = event.target
    const form = select.closest("form")
    const custom = select.value === "custom"

    this.updateCustomControls(custom)
    if (!custom && form) form.requestSubmit()
  }

  submitDate(event) {
    const value = event.target.value?.trim()
    const form = event.target.closest("form")
    if (!value || !form) return

    const range = value.split("/")
    if (range.length === 1 || (range[0] && range[1])) form.requestSubmit()
  }

  updateCustomControls(custom) {
    const customDates = this.element.querySelector("#custom-date-range")
    if (!customDates) return

    customDates.classList.toggle("hidden", !custom)
    customDates.classList.toggle("flex", custom)
    customDates.querySelectorAll('input[name="date_range"], input[name="start_date"], input[name="end_date"], input[name="as_of_date"]')
      .forEach((input) => { input.disabled = !custom })
  }
}
