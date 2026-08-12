import { Controller } from "@hotwired/stimulus"

// Progressive disclosure inside one cell of the onboarding discounts table.
//
// The record table owns the <tr>, so a row-level controller has nowhere to
// attach. It does not need one: each cell holds a select and the control that
// select governs, so this mounts once per cell and every target is optional.
//
// Pricing cell — the method and its amount share a grid. A manual discount has
// no amount at all, so the method spans the cell; a fixed one leads with the
// currency mark and a percentage trails with the sign.
//
// Scope cell — the charge picker only means anything under "only the charges I
// choose". Discounts::Save discards it under any other scope, so leaving it
// live would let an owner pick three codes and watch them vanish on save.
export default class extends Controller {
  static targets = ["typeField", "rateField", "currencyAddon", "percentAddon", "scope", "codesField"]

  connect() { this.update() }

  update() {
    if (this.hasTypeFieldTarget) this.#updatePricing()
    if (this.hasScopeTarget) this.#updateScope()
  }

  #updatePricing() {
    const pricing = this.#valueOf(this.typeFieldTarget) || "manual"
    const priced = pricing !== "manual"

    this.rateFieldTarget.hidden = !priced
    this.typeFieldTarget.classList.toggle("col-span-2", !priced)
    this.currencyAddonTarget.hidden = pricing !== "fixed"
    this.percentAddonTarget.hidden = pricing !== "percentage"
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
