import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel",
    "toggleBtn",
    "adultsCount",
    "childrenCount",
    "infantsCount",
    "roomModeResult",
    "paxModeResult",
    "roomModeLabel",
    "paxModeLabel",
    "sellModeInput",
    "baseOccupancyInput",
    "extraPaxChargeInput",
    "singleSupplementInput",
    "childMultiplierInput",
    "infantMultiplierInput",
    "basePriceInput"
  ]

  connect() {
    this.visible = false
    this.boundCalculate = this.calculate.bind(this)
    this.registerListeners()
  }

  disconnect() {
    this.unregisterListeners()
  }

  registerListeners() {
    const inputs = [
      this.sellModeInputTarget,
      this.baseOccupancyInputTarget,
      this.extraPaxChargeInputTarget,
      this.singleSupplementInputTarget,
      this.childMultiplierInputTarget,
      this.infantMultiplierInputTarget,
      this.basePriceInputTarget
    ]
    inputs.forEach(input => {
      if (input) {
        input.addEventListener("input", this.boundCalculate)
        input.addEventListener("change", this.boundCalculate)
      }
    })
  }

  unregisterListeners() {
    const inputs = [
      this.sellModeInputTarget,
      this.baseOccupancyInputTarget,
      this.extraPaxChargeInputTarget,
      this.singleSupplementInputTarget,
      this.childMultiplierInputTarget,
      this.infantMultiplierInputTarget,
      this.basePriceInputTarget
    ]
    inputs.forEach(input => {
      if (input) {
        input.removeEventListener("input", this.boundCalculate)
        input.removeEventListener("change", this.boundCalculate)
      }
    })
  }

  toggle() {
    this.visible = !this.visible
    if (this.visible) {
      this.panelTarget.classList.remove("hidden")
      this.toggleBtnTarget.textContent = "Hide Simulator"
      this.calculate()
    } else {
      this.panelTarget.classList.add("hidden")
      this.toggleBtnTarget.textContent = "Show Simulator"
    }
  }

  incrementAdults() {
    this._step("adults", 1, 1, 8)
  }

  decrementAdults() {
    this._step("adults", -1, 1, 8)
  }

  incrementChildren() {
    this._step("children", 1, 0, 6)
  }

  decrementChildren() {
    this._step("children", -1, 0, 6)
  }

  incrementInfants() {
    this._step("infants", 1, 0, 4)
  }

  decrementInfants() {
    this._step("infants", -1, 0, 4)
  }

  _step(field, delta, min, max) {
    const target = this[`${field}CountTarget`]
    if (!target) return
    const current = Number(target.textContent.trim())
    const next = Math.max(min, Math.min(max, current + delta))
    target.textContent = String(next)
    this.calculate()
  }

  calculate() {
    const price = Number(this.basePriceInputTarget?.value || 100)
    const sellMode = this.sellModeInputTarget?.value || "per_room"
    const baseOccupancy = Number(this.baseOccupancyInputTarget?.value || 2)
    const extraPaxCharge = Number(this.extraPaxChargeInputTarget?.value || 0)
    const singleSupplement = Number(this.singleSupplementInputTarget?.value || 0)
    const childMultiplier = Number(this.childMultiplierInputTarget?.value || 1.0)
    const infantMultiplier = Number(this.infantMultiplierInputTarget?.value || 0.0)

    const adults = Number(this.adultsCountTarget.textContent.trim())
    const children = Number(this.childrenCountTarget.textContent.trim())
    const infants = Number(this.infantsCountTarget.textContent.trim())

    // 1. Calculate Per Room Mode
    let roomModePrice = price
    const billablePax = adults + children
    if (billablePax > baseOccupancy) {
      const extraGuests = billablePax - baseOccupancy
      roomModePrice += extraGuests * extraPaxCharge
    }

    // 2. Calculate Per Person (Pax) Mode
    let paxModePrice = 0
    paxModePrice += adults * price
    paxModePrice += children * price * childMultiplier
    paxModePrice += infants * price * infantMultiplier

    const totalPax = adults + children + infants
    if (totalPax === 1) {
      paxModePrice += singleSupplement
    }

    const currency = this.element.dataset.currency || "MYR"
    this.roomModeResultTarget.textContent = `${currency} ${roomModePrice.toFixed(2)}`
    this.paxModeResultTarget.textContent = `${currency} ${paxModePrice.toFixed(2)}`

    // Update labels to show which mode is active in the settings form
    if (this.hasRoomModeLabelTarget && this.hasPaxModeLabelTarget) {
      if (sellMode === "per_person") {
        this.roomModeLabelTarget.innerHTML = `Per-Room Mode:`
        this.paxModeLabelTarget.innerHTML = `Per-Pax Mode <span class="ml-1.5 rounded-full bg-emerald-50 border border-emerald-200 px-2 py-0.5 text-[10px] font-bold text-emerald-700">Active</span>`
      } else {
        this.roomModeLabelTarget.innerHTML = `Per-Room Mode <span class="ml-1.5 rounded-full bg-emerald-50 border border-emerald-200 px-2 py-0.5 text-[10px] font-bold text-emerald-700">Active</span>`
        this.paxModeLabelTarget.innerHTML = `Per-Pax Mode:`
      }
    }
  }
}
