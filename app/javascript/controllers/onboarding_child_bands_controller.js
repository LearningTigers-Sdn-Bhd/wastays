import { Controller } from "@hotwired/stimulus"

// Adds and removes child age bands, and reports whether the bands still cover
// the full child age range. The server validates coverage too — this only says
// so before the operator submits.
export default class extends Controller {
  static targets = ["rows", "row", "template", "addButton", "coverage"]
  static values = { min: { type: Number, default: 0 }, max: { type: Number, default: 17 }, limit: { type: Number, default: 4 } }

  connect() {
    this.#syncCoverage()
  }

  add() {
    if (!this.hasTemplateTarget || this.#visibleRows().length >= this.limitValue) return

    const index = `${Date.now()}-${this.rowTargets.length}`
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))
    this.rowTargets.at(-1)?.querySelector("input")?.focus()
    this.#syncCoverage()
  }

  remove(event) {
    event.currentTarget.closest("[data-onboarding-child-bands-target='row']")?.remove()
    this.#syncCoverage()
  }

  recalculate() {
    this.#syncCoverage()
  }

  #visibleRows() {
    return this.rowTargets.filter(row => !row.hidden)
  }

  #ranges() {
    return this.#visibleRows()
      .map(row => {
        const [min, max] = [...row.querySelectorAll("input[type='number']")].slice(0, 2)
        return [Number(min?.value), Number(max?.value)]
      })
      .filter(([min, max]) => Number.isFinite(min) && Number.isFinite(max) && max >= min)
      .sort((a, b) => a[0] - b[0])
  }

  // Covered means: starts at the youngest age, ends at the oldest, and each band
  // begins exactly where the previous one left off.
  #covered() {
    const ranges = this.#ranges()
    if (ranges.length === 0) return false
    if (ranges[0][0] !== this.minValue) return false
    if (ranges.at(-1)[1] !== this.maxValue) return false

    return ranges.every((range, index) => index === 0 || range[0] === ranges[index - 1][1] + 1)
  }

  #syncCoverage() {
    if (this.hasAddButtonTarget) {
      this.addButtonTarget.disabled = this.#visibleRows().length >= this.limitValue
    }
    if (!this.hasCoverageTarget) return

    const covered = this.#covered()
    this.coverageTarget.textContent = covered
      ? `Ages ${this.minValue}–${this.maxValue} fully covered.`
      : `Bands must cover ages ${this.minValue}–${this.maxValue} without a gap.`
    this.coverageTarget.classList.toggle("text-success", covered)
    this.coverageTarget.classList.toggle("text-muted-foreground", !covered)
  }
}
