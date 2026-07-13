import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "display",
    "compactDisplay",
    "adultsCount",
    "childrenCount",
    "infantsCount",
    "adultsInput",
    "childrenInput",
    "infantsInput",
    "childAgesWrapper",
    "childAgesContainer",
    "childAgeInput"
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

    if (field === "children") this._syncChildAges(next)
    this._syncDisplay()
  }

  _syncChildAges(count) {
    if (!this.hasChildAgesContainerTarget) return

    const current = this.childAgeInputTargets.length
    if (count > current) {
      for (let i = current; i < count; i++) {
        const select = document.createElement("select")
        select.name = "child_ages[]"
        select.className = "rounded-lg border border-neutral-border text-xs px-2 py-1"
        select.dataset.hotelSearchBarTarget = "childAgeInput"
        for (let age = 0; age <= 17; age++) {
          const option = document.createElement("option")
          option.value = String(age)
          option.textContent = String(age)
          select.appendChild(option)
        }
        this.childAgesContainerTarget.appendChild(select)
      }
    } else if (count < current) {
      this.childAgeInputTargets.slice(count).forEach((el) => el.remove())
    }

    if (this.hasChildAgesWrapperTarget) {
      this.childAgesWrapperTarget.classList.toggle("hidden", count === 0)
    }
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

    let displayVal = `${adults} Adults · ${children} Children`
    if (infants > 0) {
      displayVal += ` · ${infants} Infant${infants > 1 ? 's' : ''}`
    }

    this.displayTarget.textContent = displayVal
    if (this.hasCompactDisplayTarget) {
      this.compactDisplayTarget.textContent = String(adults + children + infants)
    }
  }

  _countTargetFor(field) {
    if (field === "adults") return this.adultsCountTarget
    if (field === "children") return this.childrenCountTarget
    if (field === "infants") return this.infantsCountTarget
    return null
  }

  _inputTargetFor(field) {
    if (field === "adults") return this.adultsInputTarget
    if (field === "children") return this.childrenInputTarget
    if (field === "infants") return this.infantsInputTarget
    return null
  }
}

