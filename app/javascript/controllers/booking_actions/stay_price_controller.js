import { Controller } from "@hotwired/stimulus"

// Live estimated-value preview shared by the Dates / Room / Rate Sheets. Reads
// whichever recalculation fields exist in the form and refreshes the totals when
// they change. It never rewrites <select> options, so it cannot desynchronise a
// menu — option replacement is the room editor's job.
export default class extends Controller {
  static targets = ["roomTotal", "taxTotal", "estimatedTotal", "estimatedTotalInput", "manualOverrideField", "calculationStatus"]
  static values = { url: String, guestCountry: String }

  connect() {
    this.requestSequence = 0
  }

  // The rate-plan dropdown is the only interactive recalculation field this
  // form has (dates/room type are fixed, carried only as hidden fields) — so
  // this only ever fires from picking a different rate, which prices the
  // stay from scratch and drops any hand-set total.
  changed(event) {
    if (!this.recalculationFieldIds.includes(event.target.id)) return
    if (this.hasManualOverrideFieldTarget) this.manualOverrideFieldTarget.value = ""
    this.refresh()
  }

  totalChanged() {
    clearTimeout(this.totalDebounce)
    this.totalDebounce = setTimeout(() => this.solveTotal(), 400)
  }

  // Typing a final total (tax included) re-solves the room net on the server:
  // BuildFinancialSnapshot's tax rules are the only place that knows how to
  // invert them correctly, so this never duplicates that math client-side.
  async solveTotal() {
    if (!this.hasEstimatedTotalInputTarget || !this.hasManualOverrideFieldTarget) return

    const raw = String(this.estimatedTotalInputTarget.value || "").trim()
    if (raw === "") {
      this.manualOverrideFieldTarget.value = ""
      return this.refresh()
    }
    const amount = Number(raw)
    if (!Number.isFinite(amount) || amount < 0) return

    const sequence = ++this.requestSequence
    this.status("Calculating…")
    const params = new URLSearchParams({
      room_type_id: this.field("booking_room_type_id"),
      rate_plan_id: this.field("booking_rate_selection"),
      check_in: this.field("booking_check_in"),
      check_out: this.field("booking_check_out"),
      guest_country: this.guestCountryValue || "",
      target_total: amount
    })
    try {
      const response = await fetch(`${this.urlValue}?${params}`)
      const price = await response.json()
      if (!response.ok) throw new Error(price.error || "Total could not be priced.")
      if (sequence !== this.requestSequence) return

      this.manualOverrideFieldTarget.value = price.manual_rate_override ?? ""
      if (this.hasRoomTotalTarget) this.roomTotalTarget.textContent = money(price.room_total)
      if (this.hasTaxTotalTarget) this.taxTotalTarget.textContent = money(price.tax_total)
      if (document.activeElement !== this.estimatedTotalInputTarget) {
        this.estimatedTotalInputTarget.value = money(price.total_amount)
      }
      this.status("Estimate updated")
    } catch (error) {
      if (sequence === this.requestSequence) this.status(error.message)
    }
  }

  async refresh() {
    const sequence = ++this.requestSequence
    this.status("Updating estimate…")
    const params = new URLSearchParams({
      room_type_id: this.field("booking_room_type_id"),
      rate_plan_id: this.field("booking_rate_selection"),
      check_in: this.field("booking_check_in"),
      check_out: this.field("booking_check_out"),
      guest_country: this.guestCountryValue || ""
    })
    try {
      const response = await fetch(`${this.urlValue}?${params}`)
      const price = await response.json()
      if (!response.ok) throw new Error(price.error || "Estimated value could not be calculated.")
      if (sequence !== this.requestSequence) return

      if (this.hasRoomTotalTarget) this.roomTotalTarget.textContent = money(price.room_total)
      if (this.hasTaxTotalTarget) this.taxTotalTarget.textContent = money(price.tax_total)
      if (this.hasEstimatedTotalTarget) this.estimatedTotalTarget.textContent = money(price.total_amount)
      if (this.hasEstimatedTotalInputTarget && document.activeElement !== this.estimatedTotalInputTarget) {
        this.estimatedTotalInputTarget.value = money(price.total_amount)
      }
      this.status("Estimate updated")
    } catch (error) {
      if (sequence === this.requestSequence) this.status(error.message)
    }
  }

  field(id) {
    return this.element.querySelector(`#${CSS.escape(id)}`)?.value || ""
  }

  status(text) {
    if (this.hasCalculationStatusTarget) this.calculationStatusTarget.textContent = text
  }

  get recalculationFieldIds() {
    return ["booking_check_in", "booking_check_out", "booking_room_type_id", "booking_rate_selection"]
  }
}

function money(value) {
  return Number(value || 0).toFixed(2)
}
