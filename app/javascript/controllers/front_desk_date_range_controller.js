import { Controller } from "@hotwired/stimulus"

const DAY_LABELS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

export default class extends Controller {
  static targets = ["start", "end", "display", "button", "panel", "months"]

  connect() {
    this.pendingStart = null
    this.visibleDate = this.parseDate(this.startTarget.value) || new Date()
    this.outsideClick = this.handleOutsideClick.bind(this)
    this.keydown = this.handleKeydown.bind(this)
    document.addEventListener("click", this.outsideClick)
    document.addEventListener("keydown", this.keydown)
    this.updateDisplay()
    this.render()
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClick)
    document.removeEventListener("keydown", this.keydown)
  }

  toggle(event) {
    event.stopPropagation()
    const open = this.panelTarget.classList.toggle("hidden") === false
    this.buttonTarget.setAttribute("aria-expanded", open)
    if (open) this.render()
  }

  previousMonth() {
    this.visibleDate = new Date(this.visibleDate.getFullYear(), this.visibleDate.getMonth() - 1, 1)
    this.render()
  }

  nextMonth() {
    this.visibleDate = new Date(this.visibleDate.getFullYear(), this.visibleDate.getMonth() + 1, 1)
    this.render()
  }

  selectDate(event) {
    event.stopPropagation()
    const date = event.currentTarget.dataset.date

    if (!this.pendingStart) {
      this.pendingStart = date
      this.startTarget.value = date
      this.endTarget.value = ""
      this.updateDisplay()
      this.render()
      return
    }

    if (date < this.pendingStart) {
      this.pendingStart = date
      this.startTarget.value = date
      this.endTarget.value = ""
      this.updateDisplay()
      this.render()
      return
    }

    this.endTarget.value = date
    this.pendingStart = null
    this.updateDisplay()
    this.close()
    this.element.closest("form")?.requestSubmit()
  }

  selectToday() {
    const today = this.toISO(new Date())
    this.startTarget.value = today
    this.endTarget.value = today
    this.pendingStart = null
    this.updateDisplay()
    this.close()
    this.element.closest("form")?.requestSubmit()
  }

  clearDates() {
    this.startTarget.value = ""
    this.endTarget.value = ""
    this.pendingStart = null
    this.updateDisplay()
    this.close()
    this.element.closest("form")?.requestSubmit()
  }

  handleOutsideClick(event) {
    if (!event.composedPath().includes(this.element)) this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !this.panelTarget.classList.contains("hidden")) {
      this.close()
      this.buttonTarget.focus()
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  render() {
    const firstMonth = new Date(this.visibleDate.getFullYear(), this.visibleDate.getMonth(), 1)
    const secondMonth = new Date(this.visibleDate.getFullYear(), this.visibleDate.getMonth() + 1, 1)
    this.monthsTarget.innerHTML = [
      this.monthMarkup(firstMonth),
      this.monthMarkup(secondMonth, true)
    ].join("")
  }

  monthMarkup(month, second = false) {
    const year = month.getFullYear()
    const monthIndex = month.getMonth()
    const firstDay = new Date(year, monthIndex, 1).getDay()
    const days = new Date(year, monthIndex + 1, 0).getDate()
    const headers = DAY_LABELS.map((day) => `<span class="text-center text-[10px] font-bold uppercase text-slate-400">${day}</span>`).join("")
    const blanks = Array(firstDay).fill('<span class="size-9"></span>').join("")
    const cells = Array.from({ length: days }, (_, index) => this.dayMarkup(year, monthIndex, index + 1)).join("")

    return `
      <section class="${second ? "hidden lg:block" : ""}">
        <h3 class="mb-3 text-center text-sm font-bold text-slate-900">${month.toLocaleDateString("en-MY", { month: "long", year: "numeric" })}</h3>
        <div class="grid grid-cols-7 gap-1">${headers}${blanks}${cells}</div>
      </section>
    `
  }

  dayMarkup(year, month, day) {
    const iso = this.toISO(new Date(year, month, day))
    const label = new Date(year, month, day).toLocaleDateString("en-MY", { weekday: "long", day: "numeric", month: "long", year: "numeric" })
    const start = this.startTarget.value || this.pendingStart
    const end = this.endTarget.value
    const selected = iso === start || iso === end
    const inRange = start && end && iso > start && iso < end
    const today = iso === this.toISO(new Date())
    const classes = selected
      ? "bg-blue-600 text-white shadow-sm"
      : inRange
        ? "bg-blue-50 text-blue-800"
        : today
          ? "ring-1 ring-inset ring-blue-300 text-blue-700 hover:bg-blue-50"
          : "text-slate-700 hover:bg-slate-100"

    return `<button type="button" data-action="click->front-desk-date-range#selectDate" data-date="${iso}" aria-label="${label}" aria-pressed="${selected}" class="size-9 rounded-lg text-xs font-semibold transition-colors ${classes}">${day}</button>`
  }

  updateDisplay() {
    const start = this.startTarget.value
    const end = this.endTarget.value
    if (!start) {
      this.displayTarget.textContent = "All stay dates"
      return
    }

    this.displayTarget.textContent = end
      ? `${this.formatDate(start)} - ${this.formatDate(end)}`
      : `${this.formatDate(start)} - Select end date`
  }

  formatDate(iso) {
    const date = this.parseDate(iso)
    return date ? date.toLocaleDateString("en-MY", { day: "2-digit", month: "short", year: "numeric" }) : "Select date"
  }

  parseDate(iso) {
    if (!iso) return null
    const [year, month, day] = iso.split("-").map(Number)
    return new Date(year, month - 1, day)
  }

  toISO(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }
}
