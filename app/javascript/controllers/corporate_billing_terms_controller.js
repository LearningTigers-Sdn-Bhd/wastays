import { Controller } from "@hotwired/stimulus"

// Everything that describes how an account is invoiced -- credit currency,
// credit limit, payment terms, payment auto-allocation -- only means something
// on a direct-bill relationship. A standard account settles at checkout, so it
// is never invoiced and has no credit exposure to cap. Asking an operator to
// answer those questions on a standard account invites answers that are then
// stored and never read.
//
// The payment hold is the mirror image: only a standard account holds rooms
// against a payment deadline, because a direct-bill account is invoiced after
// the stay by arrangement. It also needs an account that can take rooms at all,
// so blocks carrying the "hold" target show when the booking permission is on
// AND the "terms" blocks are hidden.
//
// Several blocks can carry either target, because the fields do not all live in
// one partial.
//
// The hidden fields are disabled so they do not submit. Credit currency is
// required, but nothing is lost: a new invitation defaults it to the hotel's
// currency, and an update leaves an unsubmitted attribute untouched.
export default class extends Controller {
  static targets = ["terms", "hold"]
  static values = { billedRelationship: { type: String, default: "direct_bill" } }

  connect() {
    this.refresh()
  }

  refresh() {
    const billed = this.relationshipControl?.value === this.billedRelationshipValue
    // No booking switch on the form means the permission is not in question
    // here, so the hold answers to the relationship alone.
    const books = this.bookingControl ? this.bookingControl.checked : true

    this.toggle(this.termsTargets, billed)
    this.toggle(this.holdTargets, !billed && books)
  }

  toggle(blocks, visible) {
    blocks.forEach((block) => {
      block.hidden = !visible
      block.classList.toggle("hidden", !visible)
      // Only the named controls. The trigger button of an enhanced select
      // manages its own disabled state, and re-enabling it here would override
      // that.
      block
        .querySelectorAll("input[name], select[name], textarea[name]")
        .forEach((control) => { control.disabled = !visible })
    })
  }

  // The select menu is a progressive enhancement over a real <select>, which
  // carries the value and emits a bubbling change when the styled menu syncs
  // back to it.
  get relationshipControl() {
    return this.element.querySelector('select[name$="[relationship_type]"]')
  }

  // The switch posts an unchecked companion under the same name, so the visible
  // control is the checkbox rather than whatever the name matches first.
  get bookingControl() {
    return this.element.querySelector('input[type="checkbox"][name$="[agent_booking_enabled]"]')
  }
}
