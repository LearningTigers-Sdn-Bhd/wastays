import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.updateCustomControls()
  }

  toggleCustom(event) {
    const select = event.target
    const form = select.closest("form")
    const value = select.value
    const custom = value === "custom"
    const single = value === "single"

    this.updateCustomControls()
    if (!custom && !single && form) form.requestSubmit()
  }

  submitDate(event) {
    const value = event.target.value?.trim()
    const form = event.target.closest("form")
    if (!value || !form) return

    const range = value.split("/")
    if (range.length === 1 || (range[0] && range[1])) form.requestSubmit()
  }

  updateCustomControls() {
    const select = this.element.querySelector('select[name="date_preset"]')
    const customDates = this.element.querySelector("#custom-date-range")
    if (!select || !customDates) return

    const value = select.value
    const custom = value === "custom"
    const single = value === "single"

    customDates.classList.toggle("hidden", !custom && !single)
    customDates.classList.toggle("flex", custom || single)

    customDates.querySelectorAll('input[name="date_range"], input[name="start_date"], input[name="end_date"], input[name="as_of_date"]')
      .forEach((input) => {
        if (input.name === "end_date") {
          input.disabled = !custom
        } else {
          input.disabled = (!custom && !single)
        }
      })

    const endInput = customDates.querySelector('input[name="end_date"]')
    if (endInput) {
      const endDiv = endInput.closest("div")
      if (endDiv) {
        endDiv.classList.toggle("hidden", !custom)
      }
    }

    const startInput = customDates.querySelector('input[name="start_date"]')
    if (startInput) {
      const startDiv = startInput.closest("div")
      if (startDiv) {
        const label = startDiv.querySelector("label")
        if (label) {
          label.textContent = single ? "Date" : "Start Date"
        }
      }
    }
  }
}
