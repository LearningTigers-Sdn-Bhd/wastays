import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "name", "kind", "category", "taxable", "taxRules", "taxList", "taxCheckbox",
    "previewName", "previewCategory", "previewTaxLines", "previewTotal"
  ]

  static values = {
    amount: Number,
    currency: String
  }

  connect() {
    this.update()
  }

  update() {
    const taxRuleVisible = !this.isTaxCategory
    const taxable = taxRuleVisible && this.hasTaxableTarget && this.taxableTarget.checked

    this.taxRulesTarget.classList.toggle("hidden", !taxRuleVisible)
    this.taxListTarget.classList.toggle("hidden", !taxable)
    this.updatePreview(taxable)
  }

  updatePreview(taxable) {
    const amount = this.amountValue || 50
    const taxLines = taxable ? this.selectedActiveTaxLines(amount) : []
    const total = taxLines.reduce((sum, line) => sum + line.amount, amount)

    this.previewNameTarget.textContent = this.nameTarget.value.trim() || "Charge"
    this.previewCategoryTarget.textContent = this.previewCategoryLabel
    this.previewTaxLinesTarget.innerHTML = taxLines.map((line) => this.taxLineTemplate(line)).join("")
    this.previewTotalTarget.textContent = this.formatMoney(total)
  }

  selectedActiveTaxLines(amount) {
    return this.taxCheckboxTargets
      .filter((checkbox) => checkbox.checked && checkbox.dataset.enabled === "true")
      .map((checkbox) => {
        const taxAmount = Number.parseFloat(checkbox.dataset.amount || "0")
        const computedAmount = checkbox.dataset.rateType === "percentage"
          ? this.roundMoney(amount * taxAmount / 100)
          : this.roundMoney(taxAmount)

        return {
          name: checkbox.dataset.name || "Tax",
          amount: computedAmount
        }
      })
      .filter((line) => line.amount > 0)
  }

  taxLineTemplate(line) {
    return `
      <div class="grid grid-cols-[1fr_auto] items-center gap-4 border-t border-slate-100 px-3 py-2 text-xs">
        <div class="min-w-0">
          <p class="truncate font-semibold text-slate-800">${this.escapeHtml(line.name)}</p>
          <p class="mt-0.5 text-[9px] font-bold uppercase tracking-wider text-slate-500">Charge · Tax</p>
        </div>
        <p class="font-mono font-bold tabular-nums text-emerald-700">+${this.currencyValue} ${this.formatMoney(line.amount)}</p>
      </div>
    `
  }

  get isTaxCategory() {
    return this.kindTarget.value === "tax" || this.categoryTarget.value === "tax"
  }

  get previewCategoryLabel() {
    const kind = this.humanize(this.kindTarget.value || "charge")
    const category = this.humanize(this.categoryTarget.value || "other")
    return `${kind} · ${category}`
  }

  formatMoney(value) {
    return this.roundMoney(value).toFixed(2)
  }

  roundMoney(value) {
    return Math.round((Number(value) + Number.EPSILON) * 100) / 100
  }

  humanize(value) {
    return value
      .toString()
      .replace(/_/g, " ")
      .replace(/\w\S*/g, (word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
  }

  escapeHtml(value) {
    const element = document.createElement("div")
    element.textContent = value
    return element.innerHTML
  }
}
