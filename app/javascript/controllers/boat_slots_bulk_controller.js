import { Controller } from "@hotwired/stimulus"

// Saves every boat slot row that's still dirty in one request, instead of the
// old flow where each row had to be submitted on its own. It never rebuilds
// the field values itself -- it just re-reads each dirty row's own (never
// submitted) form via FormData, re-namespaces the fields by slot id, and
// posts them all together to the bulk endpoint as one plain form submission,
// so the page reloads with a normal Rails flash notice like every other form
// on this page.
export default class extends Controller {
  static targets = ["bar", "count"]
  static values = { url: String }

  refresh() {
    const count = this.dirtyForms().length
    this.barTarget.hidden = count === 0
    this.countTarget.textContent = count === 0 ? "" : `${count} boat ${count === 1 ? "slot" : "slots"} changed`
  }

  save() {
    const forms = this.dirtyForms()
    if (forms.length === 0) return

    const bulkForm = document.createElement("form")
    bulkForm.method = "post"
    bulkForm.action = this.urlValue
    bulkForm.dataset.turbo = "false"
    bulkForm.hidden = true

    this.appendHidden(bulkForm, "_method", "patch")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) this.appendHidden(bulkForm, "authenticity_token", token)

    forms.forEach((form) => {
      const slotId = form.dataset.slotId
      new FormData(form).forEach((value, key) => {
        const match = key.match(/^hotel_boat_schedule\[(.+)\]$/)
        if (!match) return
        this.appendHidden(bulkForm, `hotel_boat_schedules[${slotId}][${match[1]}]`, value)
      })
    })

    document.body.appendChild(bulkForm)
    bulkForm.submit()
  }

  discardAll() {
    this.dirtyForms().forEach((form) => {
      form.closest('[data-controller~="boat-slot"]')?.querySelector('[data-boat-slot-target="discard"]')?.click()
    })
  }

  // Only rows for an already-saved slot (they carry a slot id) count -- the
  // blank "add slot" card also runs the same dirty tracking, but it has its
  // own Add button and isn't part of a bulk save.
  dirtyForms() {
    return Array.from(this.element.querySelectorAll('form[data-boat-slot-target="form"][data-slot-id]'))
      .filter((form) => form.closest('[data-controller~="boat-slot"]')?.dataset.dirty === "true")
  }

  appendHidden(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
}
