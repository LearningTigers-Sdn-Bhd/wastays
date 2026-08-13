import { Controller } from "@hotwired/stimulus"

// Progressive disclosure inside one cell of an onboarding record table.
//
// The record table owns the <tr>, so a row-level controller has nowhere to
// attach. It does not need one: each cell holds a select and the control that
// select governs, so this mounts once per cell and every target is optional.
//
// Rate cell — the rate type and its figure share a grid. The figure carries the
// mark of the type holding it: a percentage trails the sign, and anything else
// leads with the currency. A type that means "staff enters the amount" has no
// figure at all, so it spans the cell; taxes have no such type and always show
// one, which is why the naming here is by role rather than by value.
//
// Scope cell — the charge picker only means anything under "only the charges I
// choose". Discounts::Save discards it under any other scope, so leaving it
// live would let an owner pick three codes and watch them vanish on save.
export default class extends Controller {
  static targets = ["typeField", "rateField", "currencyAddon", "percentAddon", "scope", "codesField"]
  static values = { unpriced: { type: String, default: "manual" }, percent: { type: String, default: "percentage" } }

  connect() { this.update() }

  update() {
    if (this.hasTypeFieldTarget) this.#updateRate()
    if (this.hasScopeTarget) this.#updateScope()
  }

  #updateRate() {
    const type = this.#valueOf(this.typeFieldTarget)
    const priced = type !== this.unpricedValue
    const percent = type === this.percentValue

    this.rateFieldTarget.hidden = !priced
    this.typeFieldTarget.classList.toggle("col-span-2", !priced)
    this.currencyAddonTarget.hidden = !priced || percent
    this.percentAddonTarget.hidden = !percent
  }

  // Nothing here is disabled, only hidden. A disabled control renders greyed —
  // and Tom Select, which enhances the charge picker, reads that state when it
  // initialises — so disabling a field on load is visible long after the field
  // is revealed. It buys nothing either: Discounts::Save nils the rate of a
  // manual discount and discards the charges of any scope but this one, so a
  // stale value cannot reach the record.
  #updateScope() {
    const chosen = (this.#valueOf(this.scopeTarget) || "all_eligible_charges") === "selected_charges"

    this.codesFieldTarget.hidden = !chosen
    this.codesFieldTarget.querySelectorAll("select").forEach((select) => { select.required = chosen })
  }

  #valueOf(target) {
    return (target.matches("select") ? target : target.querySelector("select"))?.value
  }
}
