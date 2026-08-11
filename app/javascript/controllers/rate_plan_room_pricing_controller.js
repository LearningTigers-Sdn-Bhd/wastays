import { Controller } from "@hotwired/stimulus"

// Shows only the fields the chosen rate mode actually prices with, and previews
// the ladder Derived and Auto will materialise on save.
//
// The preview mirrors RatePlans::OccupancyLadder deliberately: a hotelier
// choosing "increase by 180 per extra adult" is entitled to see the four numbers
// that produces before committing to them. The server stays the authority — this
// only ever writes to a <p>.
export default class extends Controller {
  static targets = ["mode", "manualPanel", "derivedPanel", "autoPanel", "ladderPanel", "preview"]
  static values = { anchor: Number, maxAdults: Number, currency: String, perPerson: Boolean }

  connect() {
    this.refresh()
  }

  refresh() {
    const mode = this.currentMode
    this.toggle(this.manualPanelTargets, mode === "manual")
    this.toggle(this.derivedPanelTargets, mode === "derived")
    this.toggle(this.autoPanelTargets, mode === "auto")
    this.toggle(this.ladderPanelTargets, mode === "derived" || mode === "auto")
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
      this.previewTarget.textContent = ""
      return
    }

    const anchor = mode === "auto" ? this.field("default_rate") : this.derivedAnchor()
    if (anchor === null || Number.isNaN(anchor)) {
      this.previewTarget.textContent = this.perPersonValue
        ? "Enter a rate to preview the ladder."
        : "Enter an adjustment to preview the nightly price."
      return
    }

    // A per-room plan prices the room once. Stepping through adult counts here
    // would print the same figure max_adults times and imply an occupancy
    // matrix this plan does not have.
    if (!this.perPersonValue) {
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
      rungs.push(`${adults}p ${this.money(Math.max(price, 0))}`)
    }

    this.previewTarget.textContent = `${this.currencyValue} ${rungs.join(" · ")}`
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
