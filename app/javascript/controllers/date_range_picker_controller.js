import { Controller } from "@hotwired/stimulus"

const DAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

export default class extends Controller {
  static targets = ["checkIn", "checkOut", "dateDisplay"]

  connect() {
    this.open = false
    this.selecting = null
    this.hovered = null
    const today = new Date()
    this.viewYear = today.getFullYear()
    this.viewMonth = today.getMonth()
    this._buildCalendarEl()
    this._syncDisplayFromInputs()
    document.addEventListener("click", this._onOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._onOutsideClick)
    if (this.calendarEl) this.calendarEl.remove()
  }

  openPicker(e) {
    e.stopPropagation()
    if (this.open) {
      this.closePicker()
      return
    }

    this._navigateToSelectedMonth()
    this.open = true
    this.calendarEl.classList.remove("hidden", "opacity-0", "scale-95")
    this.calendarEl.classList.add("opacity-100", "scale-100")
    this._render()
  }

  closePicker() {
    this.open = false
    this.hovered = null
    this.calendarEl.classList.add("hidden", "opacity-0", "scale-95")
    this.calendarEl.classList.remove("opacity-100", "scale-100")
  }

  clear() {
    this.selecting = null
    this.hovered = null
    this.checkInTarget.value = ""
    this.checkOutTarget.value = ""
    if (this.hasDateDisplayTarget) this.dateDisplayTarget.textContent = "Select dates"
    this._render()
  }

  prevMonth() {
    this.viewMonth--
    if (this.viewMonth < 0) { this.viewMonth = 11; this.viewYear-- }
    this._render()
  }

  nextMonth() {
    this.viewMonth++
    if (this.viewMonth > 11) { this.viewMonth = 0; this.viewYear++ }
    this._render()
  }

  hoverDay(e) {
    const iso = e.currentTarget.dataset.date
    if (!iso || !this.selecting) return
    if (iso === this.hovered) return
    this.hovered = iso
    this._render()
    this._updateDisplay(this.selecting, iso)
  }

  pickDay(e) {
    const iso = e.currentTarget.dataset.date
    if (!iso) return

    if (!this.selecting || iso <= this.selecting) {
      this.selecting = iso
      this.hovered = null
      this.checkInTarget.value = iso
      this.checkOutTarget.value = ""
      this._updateDisplay(iso, null)
    } else {
      this.checkOutTarget.value = iso
      this._updateDisplay(this.selecting, iso)
      this.selecting = null
      this.hovered = null
      this.closePicker()
    }
    this._render()
  }

  // ── Private ─────────────────────────────────────────────────

  _buildCalendarEl() {
    const el = document.createElement("div")
    el.dataset.dateRangePickerPanel = ""
    el.className = "hidden absolute left-1/2 top-full z-[200] mt-4 w-[calc(100vw-1.5rem)] -translate-x-1/2 bg-white rounded-3xl shadow-2xl border border-neutral-border p-6 transition-all duration-200 opacity-0 scale-95 sm:w-max"
    el.style.position = "absolute"
    el.addEventListener("click", (e) => e.stopPropagation())
    this.element.style.position = "relative"
    this.element.appendChild(el)
    this.calendarEl = el
  }

  _render() {
    const dual = window.matchMedia("(min-width: 1024px)").matches
    const months = dual
      ? [this._monthData(this.viewYear, this.viewMonth),
         this._monthData(...this._nextMonth(this.viewYear, this.viewMonth))]
      : [this._monthData(this.viewYear, this.viewMonth)]

    const rangeStart = this.checkInTarget.value || this.selecting
    const rangeEnd = this.checkOutTarget.value ||
                     (this.selecting && this.hovered && this.hovered > this.selecting ? this.hovered : null)

    let nights = 0
    if (rangeStart && rangeEnd) {
      nights = Math.round((new Date(rangeEnd) - new Date(rangeStart)) / (1000 * 60 * 60 * 24))
    }

    const monthLabels = months.map(m => `<span class="text-base font-bold text-neutral-900 w-52 text-center tracking-tight">${m.label}</span>`).join("")
    const monthGrids = months.map(m => this._renderMonth(m, rangeStart, rangeEnd)).join("")
    const nightsHtml = nights > 0 ? `<span class="text-sm font-bold text-neutral-900 bg-neutral-100 px-3.5 py-1 rounded-full border border-neutral-border shadow-sm">${nights} ${nights === 1 ? "night" : "nights"}</span>` : ""

    let hintHtml = ""
    if (this.selecting) {
      hintHtml = `<span class="text-[11px] font-bold text-brand-primary py-1.5 px-4 bg-brand-primary/10 rounded-full border border-brand-primary/20">Select check-out date</span>`
    } else if (!rangeStart) {
      hintHtml = `<span class="text-[11px] font-bold text-neutral-500 py-1.5 px-4 bg-neutral-100 rounded-full border border-neutral-border">Select check-in date</span>`
    }

    const frag = document.createDocumentFragment()
    const wrapper = document.createElement("div")

    // Build the calendar HTML safely
    const closeBtn = document.createElement("button")
    closeBtn.type = "button"
    closeBtn.className = "absolute top-4 right-4 p-2 rounded-full hover:bg-neutral-100 text-neutral-400 transition-colors lg:hidden z-[210]"
    closeBtn.setAttribute("data-action", "click->date-range-picker#closePicker")
    closeBtn.innerHTML = '<svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></svg>'

    // Header
    const header = document.createElement("div")
    header.className = "flex items-center justify-between mb-6 gap-x-6 pr-8 lg:pr-0"
    header.innerHTML = `
      <button type="button" data-action="click->date-range-picker#prevMonth"
              class="p-2 rounded-full hover:bg-neutral-100 text-neutral-600 transition-colors border border-neutral-border shadow-sm">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="m15 18-6-6 6-6"/></svg>
      </button>
      <div class="flex gap-x-12">${monthLabels}</div>
      <button type="button" data-action="click->date-range-picker#nextMonth"
              class="p-2 rounded-full hover:bg-neutral-100 text-neutral-600 transition-colors border border-neutral-border shadow-sm">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg>
      </button>`

    // Month grids
    const grids = document.createElement("div")
    grids.className = "flex flex-col lg:flex-row gap-x-10 gap-y-8"
    grids.innerHTML = monthGrids

    // Footer
    const footer = document.createElement("div")
    footer.className = "mt-6 pt-5 border-t border-neutral-border flex items-center justify-between min-h-[44px]"
    footer.innerHTML = `
      <div class="flex-1 flex items-center">${nightsHtml}</div>
      <div class="flex-1 flex justify-center">${hintHtml}</div>
      <div class="flex-1 flex justify-end">
        <button type="button" data-action="click->date-range-picker#clear"
                class="text-sm font-bold text-neutral-900 hover:text-brand-primary transition-colors underline decoration-2 underline-offset-4">Clear</button>
      </div>`

    wrapper.appendChild(closeBtn)
    wrapper.appendChild(header)
    wrapper.appendChild(grids)
    wrapper.appendChild(footer)
    frag.appendChild(wrapper)

    // Clear and rebuild
    while (this.calendarEl.firstChild) {
      this.calendarEl.removeChild(this.calendarEl.firstChild)
    }
    this.calendarEl.appendChild(frag)
  }

  _renderMonth({ days }, rangeStart, rangeEnd) {
    const headers = DAYS.map(d =>
      `<div class="w-12 text-[11px] font-bold text-neutral-400 text-center uppercase tracking-wider">${d}</div>`
    ).join("")

    const today = this._isoToday()

    const cells = days.map((d) => {
      if (!d) return `<div class="w-12 h-12"></div>`

      const isPast = d.iso < today
      const isStart = d.iso === rangeStart
      const isEnd = d.iso === rangeEnd
      const inRange = rangeStart && rangeEnd && d.iso > rangeStart && d.iso < rangeEnd
      const isHover = this.selecting && this.hovered === d.iso

      let rangeBg = ""
      if (inRange) {
        rangeBg = "bg-brand-primary/[0.08]"
      } else if (isStart && rangeEnd) {
        rangeBg = "bg-brand-primary/[0.08] rounded-l-full"
      } else if (isEnd) {
        rangeBg = "bg-brand-primary/[0.08] rounded-r-full"
      } else if (isHover && !rangeEnd && this.selecting) {
        rangeBg = "bg-neutral-100 rounded-full"
      }

      let circleCls = "w-10 h-10 flex items-center justify-center rounded-full transition-all duration-150 relative z-10 "
      if (isStart || isEnd) {
        circleCls += "bg-brand-primary text-white shadow-md scale-105"
      } else if (isPast) {
        circleCls += "opacity-25 cursor-not-allowed text-neutral-400"
      } else if (isHover) {
        circleCls += "bg-brand-primary/10 text-brand-primary cursor-pointer"
      } else {
        circleCls += "hover:bg-neutral-100 cursor-pointer text-neutral-900"
      }

      if (d.iso === today && !isStart && !isEnd) {
        circleCls += " ring-1 ring-inset ring-brand-primary/30"
      }

      const numCls = `text-sm font-bold ${isStart || isEnd ? "text-white" : "text-neutral-900"}`
      const attrs = isPast ? "" :
        `data-action="click->date-range-picker#pickDay mouseenter->date-range-picker#hoverDay" data-date="${d.iso}"`

      return `
        <div class="w-12 h-12 flex items-center justify-center relative">
          ${rangeBg ? `<div class="absolute inset-y-1 inset-x-0 ${rangeBg} z-0"></div>` : ""}
          <div class="${circleCls}" ${attrs}>
            <span class="${numCls}">${d.day}</span>
          </div>
        </div>`
    }).join("")

    return `
      <div>
        <div class="grid grid-cols-7 mb-3">${headers}</div>
        <div class="grid grid-cols-7">${cells}</div>
      </div>`
  }

  _monthData(year, month) {
    const label = new Date(year, month, 1).toLocaleDateString("en-MY", { month: "long", year: "numeric" })
    const firstDow = new Date(year, month, 1).getDay()
    const daysInMonth = new Date(year, month + 1, 0).getDate()
    const days = []
    for (let i = 0; i < firstDow; i++) days.push(null)
    for (let d = 1; d <= daysInMonth; d++) {
      days.push({ day: d, iso: `${year}-${String(month + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}` })
    }
    return { year, month, label, days }
  }

  _nextMonth(year, month) {
    return month === 11 ? [year + 1, 0] : [year, month + 1]
  }

  _navigateToSelectedMonth() {
    const iso = this.checkInTarget.value || this.checkOutTarget.value
    if (!iso) return
    const [y, m] = iso.split("-").map(Number)
    this.viewYear = y
    this.viewMonth = m - 1
  }

  _syncDisplayFromInputs() {
    if (!this.hasDateDisplayTarget) return
    const ci = this.checkInTarget.value
    const co = this.checkOutTarget.value
    if (ci && co) {
      this._updateDisplay(ci, co)
    } else if (ci) {
      this._updateDisplay(ci, null)
    }
  }

  _isoToday() {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
  }

  _updateDisplay(checkIn, checkOut) {
    if (!this.hasDateDisplayTarget) return
    const fmt = (iso) => {
      if (!iso) return "..."
      const [y, m, d] = iso.split("-").map(Number)
      return new Date(y, m - 1, d).toLocaleDateString("en-MY", { weekday: "short", day: "numeric", month: "short" })
    }

    if (checkIn && checkOut) {
      this.dateDisplayTarget.textContent = `${fmt(checkIn)} → ${fmt(checkOut)}`
    } else if (checkIn) {
      this.dateDisplayTarget.textContent = `${fmt(checkIn)} → Select check-out`
    } else {
      this.dateDisplayTarget.textContent = "Select dates"
    }
  }

  _onOutsideClick = (e) => {
    if (this.open && !this.element.contains(e.target) && !this.calendarEl.contains(e.target)) {
      this.closePicker()
    }
  }
}
