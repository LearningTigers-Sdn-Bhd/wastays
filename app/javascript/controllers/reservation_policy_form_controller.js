import { Controller } from "@hotwired/stimulus"

// Progressive disclosure for a stay-event policy sheet.
//
// The gate switch comes first: with it off there is nothing to configure, so
// nothing else renders. What appears beneath it is driven by the pricing type —
// a manual policy has no amount at all, a percentage needs a basis, nights needs
// a count. The cancellation sheet adds a tier repeater (INDEX-template pattern,
// as in rate_plan_age_bands_controller) plus a refund block that only matters
// once a band keeps less than everything.
export default class extends Controller {
  static targets = [
    "gate", "settings", "sentence", "pricingType", "rateField", "rateValue",
    "currencyAddon", "percentAddon", "basisField", "overrideField",
    "rows", "row", "template", "example", "refundBlock",
    "tierPricingType", "tierRateValue", "tierBasisField"
  ]
  static values = { currency: String, policyType: String }

  // A fixed illustration, so the example reads the same for every hotel.
  static SAMPLE = { total: 900, nights: 3, daysOut: 10 }

  connect() {
    this.nextIndex = Date.now()
    this.update()
  }

  update() {
    const charging = this.gateTarget.checked
    this.settingsTarget.hidden = !charging
    this.settingsTarget.querySelectorAll("input, select, textarea, button").forEach((control) => {
      control.disabled = !charging
    })
    if (!charging) return

    const pricing = this.readValue(this.pricingTypeTarget) || "manual"
    this.rateFieldTarget.hidden = pricing === "manual"
    this.basisFieldTarget.hidden = pricing !== "percentage"
    if (this.hasCurrencyAddonTarget) this.currencyAddonTarget.hidden = pricing !== "fixed"
    if (this.hasPercentAddonTarget) this.percentAddonTarget.hidden = pricing !== "percentage"
    if (this.hasOverrideFieldTarget) this.overrideFieldTarget.hidden = pricing === "manual"
    if (this.hasRateValueTarget) {
      this.rateValueTarget.step = pricing === "nights" ? "1" : "0.01"
      this.rateValueTarget.max = pricing === "percentage" ? "100" : ""
    }
    this.sentenceTarget.textContent = this.sentenceFor(pricing)

    this.tierRows().forEach((row) => this.syncTierRow(row))
    if (this.hasRefundBlockTarget) this.syncRefund()
    if (this.hasExampleTarget) this.exampleTarget.textContent = this.workedExample()
  }

  sentenceFor(pricing) {
    const event = this.policyTypeValue.replace(/_/g, " ")
    const amount = Number(this.rateValueTarget?.value || 0)
    if (pricing === "manual") return `Staff name the ${event} charge when they post it.`
    if (pricing === "fixed") return `Every ${event} is charged ${this.currencyValue} ${amount.toFixed(2)}.`
    if (pricing === "nights") {
      const nights = Math.max(0, Math.trunc(amount))
      return `Every ${event} is charged ${nights} ${nights === 1 ? "night" : "nights"} at the booking's room rate.`
    }
    return `Every ${event} is charged ${amount}% of the basis below.`
  }

  // ---- Tier repeater ------------------------------------------------------

  addTier(event) {
    event.preventDefault()
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", this.nextIndex++))
    this.update()
  }

  // A persisted row is flagged for destruction rather than removed, so Rails can
  // delete it; an unsaved row has nothing to tell the server about.
  removeTier(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-reservation-policy-form-target~='row']")
    if (!row) return

    const id = row.querySelector("input[name*='[id]']")
    const destroy = row.querySelector("[data-role='destroy']")
    if (id?.value && destroy) {
      destroy.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
    this.update()
  }

  tierRows() {
    return this.rowTargets.filter((row) => !row.hidden)
  }

  syncTierRow(row) {
    const pricing = this.readValue(row.querySelector("[data-reservation-policy-form-target~='tierPricingType']")) || "percentage"
    const basis = row.querySelector("[data-reservation-policy-form-target~='tierBasisField']")
    if (basis) basis.hidden = pricing !== "percentage"
  }

  // ---- Refund and example -------------------------------------------------

  // Only worth asking about once some band keeps less than the whole booking.
  syncRefund() {
    const anyPartial = this.tierRows().some((row) => {
      const pricing = this.readValue(row.querySelector("[data-reservation-policy-form-target~='tierPricingType']")) || "percentage"
      const value = Number(row.querySelector("[data-reservation-policy-form-target~='tierRateValue']")?.value || 0)
      return pricing === "percentage" ? value < 100 : true
    })
    this.refundBlockTarget.hidden = !anyPartial
    this.refundBlockTarget.querySelectorAll("input, select").forEach((control) => { control.disabled = !anyPartial })
  }

  workedExample() {
    const { total, nights, daysOut } = this.constructor.SAMPLE
    const perNight = total / nights
    const matched = this.tierRows()
      .map((row) => ({
        days: Number(row.querySelector("input[name*='[days_before_arrival]']")?.value ?? NaN),
        pricing: this.readValue(row.querySelector("[data-reservation-policy-form-target~='tierPricingType']")) || "percentage",
        value: Number(row.querySelector("[data-reservation-policy-form-target~='tierRateValue']")?.value || 0)
      }))
      .filter((tier) => Number.isFinite(tier.days) && daysOut >= tier.days)
      .sort((first, second) => second.days - first.days)[0]

    const money = (amount) => `${this.currencyValue} ${Math.max(0, amount).toFixed(2)}`
    const sample = `A ${money(total)} booking cancelled ${daysOut} days out`
    if (!matched) return `${sample}: no band matches, so the charge above applies.`

    let fee = 0
    if (matched.pricing === "percentage") fee = total * matched.value / 100
    else if (matched.pricing === "nights") fee = perNight * Math.trunc(matched.value)
    else fee = matched.value
    fee = Math.min(Math.max(fee, 0), total)

    return `${sample}: keep ${money(fee)}, refund ${money(total - fee)}.`
  }

  readValue(target) {
    if (!target) return ""
    const inner = target.querySelector?.("select, input")
    return inner ? inner.value : (target.value ?? "")
  }
}
