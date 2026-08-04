import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "charge", "amount", "quantity", "quantityField", "fingerprint", "pricingHint",
    "immediateField", "scheduleFields", "startsOn", "endsOn", "unitRate",
    "schedulePreview", "scheduleStatus", "scheduleRows", "scheduleTotal",
    "baseTotal", "taxTotal", "projectedTotal", "submit", "descriptionField", "description"
  ]
  static values = { charges: Object, currency: String, quoteUrl: String }

  connect() {
    this.quoteRequest = 0
    this.update()
  }

  update() {
    const charge = this.selectedCharge
    this.setDescriptionMode(charge)
    if (!charge) {
      this.setScheduling(false)
      this.amountTarget.readOnly = false
      this.quantityFieldTarget.hidden = true
      this.fingerprintTarget.value = ""
      this.pricingHintTarget.textContent = "Select an extra charge to see its pricing."
      return
    }

    if (charge.nightly) {
      this.setScheduling(true, charge)
      this.queueScheduleQuote()
      return
    }

    this.setScheduling(false)

    const folioId = this.selectedFolioId
    const preview = charge.bases?.[folioId] || Object.values(charge.bases || {})[0] || {}
    const perItem = charge.pricing_type === "fixed" && charge.charging_unit === "per_item"
    this.quantityFieldTarget.hidden = !perItem

    if (charge.pricing_type === "manual") {
      this.amountTarget.readOnly = false
      this.pricingHintTarget.textContent = "Enter the amount to charge."
      this.fingerprintTarget.value = ""
      return
    }

    if (charge.pricing_type === "fixed") {
      const quantity = perItem ? Number.parseFloat(this.quantityTarget.value || "1") : Number.parseFloat(preview.quantity || "1")
      const amount = Number.parseFloat(charge.rate_value || "0") * quantity
      this.amountTarget.readOnly = !charge.allow_amount_override
      this.pricingHintTarget.textContent = `${this.currencyValue} ${Number.parseFloat(charge.rate_value || "0").toFixed(2)} × ${quantity}`
      this.fingerprintTarget.value = ""
      if (charge.allow_amount_override && event?.target === this.amountTarget) return

      this.amountTarget.value = amount > 0 ? amount.toFixed(2) : ""
      return
    }

    this.amountTarget.value = preview.amount || ""
    this.amountTarget.readOnly = true
    this.fingerprintTarget.value = preview.fingerprint || ""
    this.pricingHintTarget.textContent = `${charge.rate_value}% of ${this.currencyValue} ${Number.parseFloat(preview.base_amount || "0").toFixed(2)}`
  }

  setDescriptionMode(charge) {
    const manual = charge?.pricing_type === "manual"
    this.descriptionFieldTarget.hidden = !manual
    this.descriptionTarget.disabled = !manual
  }

  setScheduling(enabled, charge = null) {
    this.immediateFieldTargets.forEach((field) => { field.hidden = enabled })
    this.scheduleFieldsTargets.forEach((field) => { field.hidden = !enabled })
    this.schedulePreviewTarget.hidden = !enabled
    this.amountTarget.disabled = enabled
    this.element.querySelector("input[name='folio_transaction[posting_date]']").disabled = enabled
    this.startsOnTarget.disabled = !enabled
    this.endsOnTarget.disabled = !enabled
    this.unitRateTarget.disabled = !enabled
    this.quantityFieldTarget.hidden = true
    if (!enabled) {
      this.submitTarget.textContent = "Add charge"
      this.submitTarget.disabled = false
      return
    }

    this.submitTarget.textContent = "Schedule charges"

    if (!this.unitRateTarget.value || this.lastChargeId !== this.nativeSelectValue(this.chargeTarget)) {
      this.unitRateTarget.value = Number.parseFloat(charge.rate_value || "0").toFixed(2)
      this.startsOnTarget.value = ""
      this.endsOnTarget.value = ""
    }
    this.unitRateTarget.readOnly = !charge.allow_amount_override
    this.lastChargeId = this.nativeSelectValue(this.chargeTarget)
  }

  queueScheduleQuote() {
    window.clearTimeout(this.quoteTimer)
    this.quoteTimer = window.setTimeout(() => this.loadScheduleQuote(), 120)
  }

  async loadScheduleQuote() {
    const requestId = ++this.quoteRequest
    this.schedulePreviewTarget.setAttribute("aria-busy", "true")
    this.scheduleStatusTarget.textContent = "Calculating dated charges…"
    this.submitTarget.disabled = true

    const params = new URLSearchParams({
      hotel_extra_charge_id: this.nativeSelectValue(this.chargeTarget),
      booking_folio_id: this.selectedFolioId,
      unit_rate: this.unitRateTarget.value
    })
    if (this.startsOnTarget.value) params.set("starts_on", this.startsOnTarget.value)
    if (this.endsOnTarget.value) params.set("ends_on", this.endsOnTarget.value)

    try {
      const response = await fetch(`${this.quoteUrlValue}?${params.toString()}`, { headers: { Accept: "application/json" } })
      const payload = await response.json()
      if (requestId !== this.quoteRequest) return
      if (!response.ok) throw new Error(payload.error || "Dated charges could not be calculated.")
      this.applyScheduleQuote(payload)
      this.submitTarget.disabled = false
    } catch (error) {
      if (requestId !== this.quoteRequest) return
      this.fingerprintTarget.value = ""
      this.scheduleRowsTarget.replaceChildren()
      this.scheduleStatusTarget.textContent = error.message
    } finally {
      if (requestId === this.quoteRequest) this.schedulePreviewTarget.setAttribute("aria-busy", "false")
    }
  }

  applyScheduleQuote(payload) {
    this.startsOnTarget.min = payload.allowed_dates[0]
    this.startsOnTarget.max = payload.allowed_dates[payload.allowed_dates.length - 1]
    this.endsOnTarget.min = payload.allowed_dates[0]
    this.endsOnTarget.max = payload.allowed_dates[payload.allowed_dates.length - 1]
    if (!this.startsOnTarget.value) this.startsOnTarget.value = payload.starts_on
    if (!this.endsOnTarget.value) this.endsOnTarget.value = payload.ends_on
    this.fingerprintTarget.value = payload.fingerprint
    this.scheduleStatusTarget.textContent = `${payload.dates.length} ${payload.dates.length === 1 ? "date" : "dates"} · rate ${this.money(payload.unit_rate)} per unit`
    this.scheduleTotalTarget.textContent = this.money(payload.grand_total)
    this.baseTotalTarget.textContent = this.money(payload.base_total)
    this.taxTotalTarget.textContent = this.money(payload.tax_total)
    this.projectedTotalTarget.textContent = this.money(payload.grand_total)
    this.scheduleRowsTarget.replaceChildren(...payload.dates.map((row) => this.dateRow(row)))
  }

  dateRow(row) {
    const container = document.createElement("div")
    container.className = "space-y-1 border-t border-border pt-2 first:border-0 first:pt-0"
    const heading = document.createElement("div")
    heading.className = "flex items-center justify-between gap-3 text-xs"
    const date = document.createElement("span")
    date.className = "font-semibold text-foreground"
    date.textContent = `${row.date} · ${row.posting_state === "immediate" ? "Posts now" : "Upcoming"}`
    const total = document.createElement("span")
    total.className = "font-semibold tabular-nums text-foreground"
    total.textContent = this.money(row.total)
    heading.append(date, total)
    container.append(heading)
    const quantity = Number.parseFloat(row.quantity || "1")
    const calculation = quantity > 1 ? `${quantity} × ${this.money(row.unit_rate)}` : this.money(row.unit_rate)
    container.append(this.lineRow(`${this.selectedCharge.name} · ${calculation}`, row.base_amount))
    row.taxes.forEach((tax) => container.append(this.lineRow(`Tax: ${tax.name}`, tax.amount)))
    return container
  }

  lineRow(label, amount) {
    const row = document.createElement("div")
    row.className = "flex items-center justify-between gap-3 text-xs text-muted-foreground"
    const name = document.createElement("span")
    name.textContent = label
    const value = document.createElement("span")
    value.className = "tabular-nums"
    value.textContent = this.money(amount)
    row.append(name, value)
    return row
  }

  money(value) {
    return `${this.currencyValue} ${Number.parseFloat(value || "0").toFixed(2)}`
  }

  get selectedCharge() {
    const value = this.nativeSelectValue(this.chargeTarget)
    return this.chargesValue[value]
  }

  get selectedFolioId() {
    const folioSelect = this.element.querySelector("select[name='folio_transaction[booking_folio_id]']")
    return folioSelect?.value || Object.keys(this.selectedCharge?.bases || {})[0]
  }

  nativeSelectValue(target) {
    const select = target.matches("select") ? target : target.querySelector("select")
    return select?.value
  }
}
