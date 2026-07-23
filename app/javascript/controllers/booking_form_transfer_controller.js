import { Controller } from "@hotwired/stimulus"

// Transfers the live Quick Booking form into the full booking sheet without
// submitting or persisting it. Transport-only Rails fields are deliberately
// excluded so CSRF tokens never appear in the GET URL.
export default class extends Controller {
  static values = { formId: String, frame: { type: String, default: "booking_action_sheet" } }

  open(event) {
    event.preventDefault()

    const form = document.getElementById(this.formIdValue)
    if (!form) return

    const url = new URL(this.element.href, window.location.origin)
    const data = new FormData(form)
    data.forEach((value, key) => {
      if (this.transportField(key) || value instanceof File) return
      url.searchParams.append(key, value)
    })

    const link = document.createElement("a")
    link.href = url.toString()
    link.dataset.turboFrame = this.frameValue
    link.hidden = true
    document.body.appendChild(link)
    link.click()
    link.remove()
  }

  transportField(key) {
    return ["authenticity_token", "_method", "utf8"].includes(key)
  }
}
