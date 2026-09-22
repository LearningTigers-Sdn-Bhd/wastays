import { Controller } from "@hotwired/stimulus"

// Identifier: agent-guest-identity
//
// One instance per guest row in the corporate portal's booking form. Two
// things follow the nationality field: whether the ID field reads "IC" or
// "Passport" (Malaysia gets the first, everyone else the second -- it never
// asks the agent to say which kind), and, for a Malaysian IC, the date of
// birth -- read straight from its first six digits, the same rule
// Guest#populate_date_of_birth_from_malaysian_ic applies server-side (see
// app/lib/guests/malaysian_ic_date_of_birth_parser.rb), kept in step here so
// the field visibly updates as the agent types rather than only on submit.
//
// Looked up by name suffix rather than Stimulus targets: the IC and date of
// birth inputs are plain PanelsUI::Input controls, but the nationality field
// is a PanelsUI::Combobox, whose progressive-enhancement wrapper does not
// forward a caller's own `data-*-target` down to the native <select> it
// manages -- the same limitation the view's own comments already work around
// for `name:`.
export default class extends Controller {
  connect() {
    this.icInput = this.element.querySelector('input[name$="[government_id]"]')
    this.countrySelect = this.element.querySelector('select[name$="[country]"]')
    this.dobInput = this.element.querySelector('input[name$="[date_of_birth]"]')
    if (!this.icInput || !this.countrySelect || !this.dobInput) return

    this.icLabel = this.icInput.closest(".panel-form-field")?.querySelector("label")

    this.onIcInput = () => this.refresh()
    this.onCountryChange = () => this.refresh()
    // A DOB the agent edits by hand is never overwritten again -- only one
    // this controller filled in itself is fair game to replace or clear. The
    // value is compared, not just "did an input event fire": a native date
    // input fires one from merely tabbing through its day/month/year segments,
    // with nothing actually changed, and treating that alone as a manual edit
    // would permanently stop a later, genuinely different IC from updating it.
    this.onDobInput = () => {
      if (this.dobInput.value === this.lastWrittenDob) return

      delete this.dobInput.dataset.autofilled
    }

    this.icInput.addEventListener("input", this.onIcInput)
    this.countrySelect.addEventListener("change", this.onCountryChange)
    this.dobInput.addEventListener("input", this.onDobInput)
    this.refresh()
  }

  disconnect() {
    this.icInput?.removeEventListener("input", this.onIcInput)
    this.countrySelect?.removeEventListener("change", this.onCountryChange)
    this.dobInput?.removeEventListener("input", this.onDobInput)
  }

  refresh() {
    this.updateLabel()

    // A passport number is genuinely alphanumeric -- no format to check it
    // against here beyond the field's own max length -- so only a Malaysian
    // IC gets validated, and only there does typing one drive the date of
    // birth.
    if (!this.isMalaysia()) {
      this.setError("")
      this.clearAutofilledDob()
      return
    }

    this.validateIc()
  }

  validateIc() {
    const raw = this.icInput.value

    // Letters silently fell out of the digit count before, so "9902031z2666"
    // passed as if it read "990203126661" -- a stray character has to fail
    // outright, not just get stripped on the way to the date check.
    if (raw !== "" && /[^\d\s-]/.test(raw)) {
      this.setError("An IC number should contain digits only.")
      this.clearAutofilledDob()
      return
    }

    const digits = raw.replace(/\D/g, "")

    if (digits.length > 12) {
      this.setError("An IC number has at most 12 digits.")
      this.clearAutofilledDob()
      return
    }

    if (digits.length < 6) {
      this.setError("")
      this.clearAutofilledDob()
      return
    }

    const dob = this.parseIcDateOfBirth(digits)
    if (!dob) {
      this.setError("Those first 6 digits of the IC are not a valid date of birth.")
      this.clearAutofilledDob()
      return
    }

    this.setError("")
    // Never clobbers a date the agent already typed themselves -- only what
    // this controller filled in before, or an empty field.
    if (this.dobInput.value && this.dobInput.dataset.autofilled !== "true") return

    this.writeDob(dob)
  }

  isMalaysia() {
    return this.countrySelect.value.trim().toLowerCase() === "malaysia"
  }

  // "IC" for Malaysia, "Passport" for anyone else -- the field never asks the
  // agent to say which kind of number they are holding; it reads that off the
  // nationality already chosen, same as which column the server files it
  // under (CorporatePortal::CreateAgentBooking#identity_attributes).
  updateLabel() {
    const malaysia = this.isMalaysia()
    const label = malaysia ? "IC" : "Passport"

    if (this.icLabel) this.icLabel.textContent = label
    this.icInput.placeholder = `${label} number`
  }

  clearAutofilledDob() {
    if (this.dobInput.dataset.autofilled !== "true") return

    this.writeDob("")
  }

  // The one place that sets the date of birth field itself, so the "own write
  // vs. the agent's" guard in onDobInput only has one call site to protect.
  writeDob(value) {
    this.dobInput.value = value
    this.lastWrittenDob = value
    if (value) {
      this.dobInput.dataset.autofilled = "true"
    } else {
      delete this.dobInput.dataset.autofilled
    }
    this.dobInput.dispatchEvent(new Event("input", { bubbles: true }))
    this.dobInput.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Mirrors Guests::MalaysianIcDateOfBirthParser: the first six digits are
  // YYMMDD: the century is inferred from today's date, and rolled back a
  // century if that would otherwise land in the future.
  parseIcDateOfBirth(digits) {
    const yy = parseInt(digits.slice(0, 2), 10)
    const mm = parseInt(digits.slice(2, 4), 10)
    const dd = parseInt(digits.slice(4, 6), 10)
    const today = new Date()

    const roundTrips = (year) => {
      const date = new Date(year, mm - 1, dd)
      return date.getFullYear() === year && date.getMonth() === mm - 1 && date.getDate() === dd
    }

    let year = Math.floor(today.getFullYear() / 100) * 100 + yy
    if (!roundTrips(year)) return null

    let date = new Date(year, mm - 1, dd)
    if (date > today) {
      year -= 100
      if (!roundTrips(year)) return null
      date = new Date(year, mm - 1, dd)
    }

    const pad = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  }

  setError(message) {
    this.icInput.setCustomValidity(message)
    if (!message && !this.errorEl) return

    if (!this.errorEl) {
      this.errorEl = document.createElement("p")
      this.errorEl.className = "col-span-2 -mt-1.5 text-xs font-medium text-destructive"
      this.icInput.closest(".panel-form-field")?.insertAdjacentElement("afterend", this.errorEl)
    }
    this.errorEl.textContent = message
    this.errorEl.hidden = !message
  }
}
