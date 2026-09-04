import { Controller } from "@hotwired/stimulus"

// The state field is an LHDN code list, and those codes only exist for a
// Malaysian address. A guest who lives in Japan has no code to pick, so the
// field becomes a plain text box and they type the prefecture themselves.
//
// Both controls carry the same field name. The hidden one is disabled, so the
// form always submits exactly one state value.
export default class extends Controller {
  static targets = ["country", "coded", "free"]
  static values = { codedCountry: { type: String, default: "Malaysia" } }

  connect() {
    this.refresh()
  }

  refresh() {
    const coded = this.usesCodedList()
    this.toggle(this.codedTarget, coded)
    this.toggle(this.freeTarget, !coded)
  }

  // Only Malaysia has a code list. An empty country has not been confirmed as
  // Malaysian yet, so it gets the text box too.
  usesCodedList() {
    const value = (this.countryControl?.value || "").trim()

    return value.toLowerCase() === this.codedCountryValue.toLowerCase()
  }

  toggle(wrapper, visible) {
    wrapper.hidden = !visible
    wrapper.classList.toggle("hidden", !visible)
    wrapper
      .querySelectorAll("input, select, textarea, button")
      .forEach((control) => { control.disabled = !visible })
  }

  // The country field may be a plain input or a wrapper around the native
  // select that a combobox enhances. Both answer here.
  get countryControl() {
    if (!this.hasCountryTarget) return null

    return this.countryTarget.querySelector("select, input, textarea") || this.countryTarget
  }
}
