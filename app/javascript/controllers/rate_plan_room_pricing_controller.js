import { Controller } from "@hotwired/stimulus"

// Shows only the fields the chosen rate mode actually prices with, and previews
// the ladder Derived and Auto will materialise on save.
//
// The preview mirrors RatePlans::OccupancyLadder deliberately: a hotelier
// choosing "increase by 180 per extra adult" is entitled to see the four numbers
// that produces before committing to them. The server stays the authority — this
// only ever writes to a <p>.
export default class extends Controller {
  static targets = ["mode", "manualPanel", "derivedPanel", "autoPanel", "preview", "rungTemplate"]
  static values = { anchor: Number, maxAdults: Number, currency: String, perPerson: Boolean }

  connect() {
    this.refresh()
  }

  refresh() {
    const mode = this.currentMode
    this.toggle(this.manualPanelTargets, mode === "manual")
    this.toggle(this.derivedPanelTargets, mode === "derived")
    this.toggle(this.autoPanelTargets, mode === "auto")
    this.renderPreview(mode)
  }

  get currentMode() {
    const checked = this.modeTargets.find(input => input.checked)
    return checked ? checked.value : "manual"
  }

  toggle(elements, visible) {
    elements.forEach(element => element.classList.toggle("hidden", !visible))
  }

  renderPreview(mode) {
    if (!this.hasPreviewTarget) return
    if (mode !== "derived" && mode !== "auto") {
      this.resetPreviewClass()
      this.previewTarget.replaceChildren()
      return
    }

    const anchor = mode === "auto" ? this.field("default_rate") : this.derivedAnchor()
    if (anchor === null || Number.isNaN(anchor)) {
      this.resetPreviewClass()
      this.previewTarget.textContent = this.perPersonValue
        ? "Enter a rate to preview the ladder."
        : "Enter an adjustment to preview the nightly price."
      return
    }

    // A per-room plan prices the room once. Stepping through adult counts here
    // would print the same figure max_adults times and imply an occupancy
    // matrix this plan does not have.
    if (!this.perPersonValue) {
      this.resetPreviewClass()
      this.previewTarget.textContent = `${this.currencyValue} ${this.money(Math.max(anchor, 0))} per night`
      return
    }

    const primary = this.clamp(this.field("primary_occupancy") ?? 2, 1, this.maxAdultsValue)
    const increase = this.step("increase", anchor)
    const decrease = this.step("decrease", anchor)

    const rungs = []
    for (let adults = 1; adults <= this.maxAdultsValue; adults++) {
      const steps = adults - primary
      let price = anchor
      if (steps > 0) price = anchor + increase * steps
      if (steps < 0) price = anchor - decrease * Math.abs(steps)
      rungs.push({ adults, price: Math.max(price, 0) })
    }

    this.renderRungs(rungs)
  }

  // Mirrors HotelPortal::RatePlansHelper#occupancy_price_ladder's guest-count
  // tags (Room Inventory) instead of a plain "1p 200.00 · 2p 200.00" string.
  renderRungs(rungs) {
    if (!this.hasRungTemplateTarget) {
      this.previewTarget.textContent = `${this.currencyValue} ${rungs.map((rung) => `${rung.adults}p ${this.money(rung.price)}`).join(" · ")}`
      return
    }

    const nodes = rungs.map((rung) => {
      const node = this.rungTemplateTarget.content.firstElementChild.cloneNode(true)
      node.title = `${rung.adults} ${rung.adults === 1 ? "guest" : "guests"}: ${this.currencyValue} ${this.money(rung.price)}`
      node.querySelector('[data-role="count"]').textContent = rung.adults
      node.querySelector('[data-role="price"]').textContent = this.money(rung.price)
      return node
    })

    const label = document.createElement("span")
    label.className = "me-0.5 text-xs text-muted-foreground"
    label.textContent = this.currencyValue

    this.previewTarget.className = "inline-flex flex-wrap items-center gap-1.5"
    this.previewTarget.replaceChildren(label, ...nodes)
  }

  resetPreviewClass() {
    this.previewTarget.className = "text-sm text-muted-foreground"
  }

  derivedAnchor() {
    const value = this.field("derive_value")
    if (value === null) return null

    const mode = this.select("derive_mode")
    if (mode === "offset") return this.anchorValue + value
    return this.anchorValue * (1 + value / 100)
  }

  step(prefix, anchor) {
    const value = this.field(`${prefix}_by`) ?? 0
    return this.select(`${prefix}_unit`) === "percent" ? (anchor * value) / 100 : value
  }

  field(name) {
    const element = this.element.querySelector(`[name="room_pricing[${name}]"]`)
    if (!element || element.value === "") return null
    const parsed = Number.parseFloat(element.value)
    return Number.isNaN(parsed) ? null : parsed
  }

  select(name) {
    const element = this.element.querySelector(`[name="room_pricing[${name}]"]`)
    return element ? element.value : ""
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  money(value) {
    return value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
