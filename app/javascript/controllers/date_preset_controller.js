import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggleCustom(event) {
    const select = event.target
    const customDates = document.getElementById("custom-date-range")
    const form = select.closest("form")

    if (!customDates) return

    if (select.value === "custom") {
      customDates.classList.remove("hidden")
      customDates.classList.add("flex")
    } else {
      customDates.classList.add("hidden")
      customDates.classList.remove("flex")

      // Disable start/end date inputs so they don't clutter the URL
      if (form) {
        const startInput = form.querySelector('input[name="start_date"]')
        const endInput = form.querySelector('input[name="end_date"]')
        if (startInput) startInput.disabled = true
        if (endInput) endInput.disabled = true
        form.requestSubmit()
      }
    }
  }
}
