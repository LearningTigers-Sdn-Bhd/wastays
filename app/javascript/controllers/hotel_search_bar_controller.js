import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "display",
    "compactDisplay",
    "adultsCount",
    "childrenCount",
    "infantsCount",
    "roomCountCount",
    "adultsInput",
    "childrenInput",
    "infantsInput",
    "roomCountInput"
  ]

  step(event) {
    const field = event.params.field
    const delta = Number(event.params.delta)
    const min = Number(event.params.min)
    const max = Number(event.params.max)

    if (!field || Number.isNaN(delta) || Number.isNaN(min) || Number.isNaN(max)) return

    const countTarget = this._countTargetFor(field)
    const inputTarget = this._inputTargetFor(field)
    if (!countTarget || !inputTarget) return

    const current = Number(countTarget.textContent.trim())
    const next = Math.max(min, Math.min(max, current + delta))

    countTarget.textContent = String(next)
    inputTarget.value = String(next)
    this._syncDisplay()
  }

  submit(event) {
    event.preventDefault()
    const form = event.currentTarget
    const params = new URLSearchParams(new FormData(form))
    window.location.replace(`${form.action}?${params.toString()}`)
  }

  close(event) {
    if (event.target === this.element) {
      this.element.classList.add("hidden")
    }
  }

  _syncDisplay() {
    const adults = Number(this.adultsCountTarget.textContent.trim())
    const children = Number(this.childrenCountTarget.textContent.trim())
    const infants = this.hasInfantsCountTarget ? Number(this.infantsCountTarget.textContent.trim()) : 0
    const roomCount = Number(this.roomCountCountTarget.textContent.trim())
    const roomLabel = roomCount === 1 ? " Room" : " Rooms"

    let displayVal = `${adults} Adults · ${children} Children`
    if (infants > 0) {
      displayVal += ` · ${infants} Infant${infants > 1 ? 's' : ''}`
    }
    displayVal += ` · ${roomCount}${roomLabel}`

    this.displayTarget.textContent = displayVal
    if (this.hasCompactDisplayTarget) {
      this.compactDisplayTarget.textContent = String(adults + children + infants)
    }
  }

  _countTargetFor(field) {
    if (field === "adults") return this.adultsCountTarget
    if (field === "children") return this.childrenCountTarget
    if (field === "infants") return this.infantsCountTarget
    if (field === "roomCount") return this.roomCountCountTarget
    return null
  }

  _inputTargetFor(field) {
    if (field === "adults") return this.adultsInputTarget
    if (field === "children") return this.childrenInputTarget
    if (field === "infants") return this.infantsInputTarget
    if (field === "roomCount") return this.roomCountInputTarget
    return null
  }
}

