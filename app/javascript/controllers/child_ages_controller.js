import { Controller } from "@hotwired/stimulus"

// One age picker per child, kept in step with a children count field. An
// age-banded rate plan can only price a child whose age it knows, so every
// form that books a per-guest room asks for them: the travel agent search and
// the desk's booking rows. Ages already chosen survive the count changing.
//
// The count target may be a plain <input> or a PanelsUI FormField wrapper;
// either way the real value is read from the input inside it.
export default class extends Controller {
  static targets = ["count", "list", "wrapper"]
  static values = {
    name: String,
    ages: Array,
    min: { type: Number, default: 0 },
    max: { type: Number, default: 17 },
    selectAction: String
  }

  connect() {
    this.sync()
  }

  sync() {
    const count = this.count()
    const selects = Array.from(this.listTarget.querySelectorAll("select"))

    for (let index = selects.length; index < count; index++) {
      this.listTarget.appendChild(this.buildSelect(index))
    }
    selects.slice(count).forEach((select) => select.remove())

    if (this.hasWrapperTarget) this.wrapperTarget.classList.toggle("hidden", count === 0)
  }

  count() {
    const input = this.countTarget.matches("input") ? this.countTarget : this.countTarget.querySelector("input")
    const value = parseInt(input?.value || "0", 10)
    return Number.isFinite(value) && value > 0 ? Math.min(value, 10) : 0
  }

  buildSelect(index) {
    const select = document.createElement("select")
    select.name = this.nameValue
    select.required = true
    select.setAttribute("aria-label", `Age of child ${index + 1}`)
    select.className = "h-8 rounded-md border border-border bg-background px-2 text-sm text-foreground"
    if (this.selectActionValue) select.dataset.action = this.selectActionValue

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = "Age"
    select.appendChild(placeholder)

    const saved = this.agesValue[index]
    for (let age = this.minValue; age <= this.maxValue; age++) {
      const option = document.createElement("option")
      option.value = String(age)
      option.textContent = String(age)
      option.selected = saved !== undefined && saved !== null && String(saved) === String(age)
      select.appendChild(option)
    }
    return select
  }
}
