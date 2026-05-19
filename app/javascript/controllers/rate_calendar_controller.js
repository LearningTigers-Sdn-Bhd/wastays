import { Controller } from "@hotwired/stimulus"

const DAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

export default class extends Controller {
  static targets = ["checkIn", "checkOut", "dateDisplay"]
  static values = {
    url: String,
    currency: { type: String, default: "MYR" },
    roomCount: { type: Number, default: 1 },
    partnerCode: { type: String, default: "" }
  }

  connect() {
    this.cache        = new Map()
    this.loadedRanges = []
    this.open      = false
    this.selecting = null
    this.hovered   = null
    const today    = new Date()
    this.viewYear  = today.getFullYear()
    this.viewMonth = today.getMonth()
    this._buildCalendarEl()
    this._fetchAround(this.viewYear, this.viewMonth)
    document.addEventListener("click", this._onOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._onOutsideClick)
  }

  // ── Public actions ──────────────────────────────────────────

  openPicker() {
    this.open = true
    this.calendarEl.classList.remove("hidden", "opacity-0", "scale-95")
    this.calendarEl.classList.add("opacity-100", "scale-100")
    this._render()
  }

  closePicker() {
    this.open    = false
    this.hovered = null
    this.calendarEl.classList.add("hidden", "opacity-0", "scale-95")
    this.calendarEl.classList.remove("opacity-100", "scale-100")
  }

  clear() {
    this.selecting            = null
    this.hovered              = null
    this.checkInTarget.value  = ""
    this.checkOutTarget.value = ""
    if (this.hasDateDisplayTarget) this.dateDisplayTarget.textContent = "Select dates"
    this._render()
  }

  prevMonth() {
    this.viewMonth--
    if (this.viewMonth < 0) { this.viewMonth = 11; this.viewYear-- }
    this._fetchAround(this.viewYear, this.viewMonth)
    this._render()
  }

  nextMonth() {
    this.viewMonth++
    if (this.viewMonth > 11) { this.viewMonth = 0; this.viewYear++ }
    this._fetchAround(this.viewYear, this.viewMonth)
    this._render()
  }

  hoverDay(e) {
    const iso = e.currentTarget.dataset.date
    if (!iso || !this.selecting) return
    if (iso === this.hovered) return
    this.hovered = iso
    this._render()
    // Only update display text during hover — pickDay will confirm it
    this._updateDisplay(this.selecting, iso)
  }

  pickDay(e) {
    const iso = e.currentTarget.dataset.date
    if (!iso) return
    const info = this.cache.get(iso)
    if (info && !info.available) return

    if (!this.selecting || iso <= this.selecting) {
      // First pick or re-pick earlier date — set check-in
      this.selecting            = iso
      this.hovered              = null
      this.checkInTarget.value  = iso
      this.checkOutTarget.value = ""
      this._updateDisplay(iso, null)
    } else {
      // Second pick — confirm range
      this.checkOutTarget.value = iso
      this._updateDisplay(this.selecting, iso)
      this.selecting = null
      this.hovered   = null
      this.closePicker()
    }
    this._render()
  }

  // ── Private ─────────────────────────────────────────────────

  _buildCalendarEl() {
    const el = document.createElement("div")
    el.className = "hidden absolute top-full left-1/2 -translate-x-1/2 mt-3 z-[200] bg-white rounded-3xl shadow-2xl border border-neutral-border p-6 w-[95vw] sm:w-max transition-all duration-200 origin-top opacity-0 scale-95"
    el.addEventListener("click", e => e.stopPropagation())
    this.element.style.position = "relative"
    this.element.appendChild(el)
    this.calendarEl = el
  }


  _render() {
    const dual   = window.matchMedia("(min-width: 1024px)").matches
    const months = dual
      ? [this._monthData(this.viewYear, this.viewMonth),
         this._monthData(...this._nextMonth(this.viewYear, this.viewMonth))]
      : [this._monthData(this.viewYear, this.viewMonth)]

    // Determine effective range to highlight (confirmed or hover preview)
    const rangeStart = this.checkInTarget.value || this.selecting
    const rangeEnd   = this.checkOutTarget.value ||
                       (this.selecting && this.hovered && this.hovered > this.selecting ? this.hovered : null)

    let nights = 0
    if (rangeStart && rangeEnd) {
      nights = Math.round((new Date(rangeEnd) - new Date(rangeStart)) / (1000 * 60 * 60 * 24))
    }

    this.calendarEl.innerHTML = `
      <button type="button" data-action="click->rate-calendar#closePicker"
              class="absolute top-4 right-4 p-2 rounded-full hover:bg-neutral-100 text-neutral-400 transition-colors lg:hidden z-[210]">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></svg>
      </button>

      <div class="flex items-center justify-between mb-6 gap-x-6 pr-8 lg:pr-0">
        <button type="button" data-action="click->rate-calendar#prevMonth"
                class="p-2 rounded-full hover:bg-neutral-100 text-neutral-600 transition-colors border border-neutral-border shadow-sm">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="m15 18-6-6 6-6"/></svg>
        </button>
        <div class="flex gap-x-12">
          ${months.map(m => `<span class="text-base font-bold text-neutral-900 w-52 text-center tracking-tight">${m.label}</span>`).join("")}
        </div>
        <button type="button" data-action="click->rate-calendar#nextMonth"
                class="p-2 rounded-full hover:bg-neutral-100 text-neutral-600 transition-colors border border-neutral-border shadow-sm">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg>
        </button>
      </div>

      <div class="flex flex-col lg:flex-row gap-x-10 gap-y-8">
        ${months.map(m => this._renderMonth(m, rangeStart, rangeEnd)).join("")}
      </div>

      <div class="mt-6 pt-5 border-t border-neutral-border flex items-center justify-between min-h-[44px]">
        <div class="flex-1 flex items-center">
          ${nights > 0 ? `
            <span class="text-sm font-bold text-neutral-900 bg-neutral-100 px-3.5 py-1 rounded-full border border-neutral-border shadow-sm">
              ${nights} ${nights === 1 ? 'night' : 'nights'}
            </span>
          ` : ""}
        </div>
        
        <div class="flex-1 flex justify-center">
          ${this.selecting ? `
            <span class="text-[11px] font-bold text-brand-primary py-1.5 px-4 bg-brand-primary/10 rounded-full border border-brand-primary/20 animate-in fade-in zoom-in duration-300">
              Select check-out date
            </span>
          ` : !rangeStart ? `
            <span class="text-[11px] font-bold text-neutral-500 py-1.5 px-4 bg-neutral-100 rounded-full border border-neutral-border animate-in fade-in zoom-in duration-300">
              Select check-in date
            </span>
          ` : ""}
        </div>

        <div class="flex-1 flex justify-end">
          <button type="button" data-action="click->rate-calendar#clear"
                  class="text-sm font-bold text-neutral-900 hover:text-brand-primary transition-colors underline decoration-2 underline-offset-4">
            Clear
          </button>
        </div>
      </div>
    `
  }

  _renderMonth({ days }, rangeStart, rangeEnd) {
    const headers = DAYS.map(d =>
      `<div class="w-12 text-[11px] font-bold text-neutral-400 text-center uppercase tracking-wider">${d}</div>`
    ).join("")

    const today = this._isoToday()

    const cells = days.map((d) => {
      if (!d) return `<div class="w-12 h-14"></div>`

      const info     = this.cache.get(d.iso)
      const isPast   = d.iso < today
      const soldOut  = info && !info.available
      const disabled = isPast || soldOut

      const isStart  = d.iso === rangeStart
      const isEnd    = d.iso === rangeEnd
      const inRange  = rangeStart && rangeEnd && d.iso > rangeStart && d.iso < rangeEnd
      const isHover  = this.selecting && this.hovered === d.iso

      // Range background spans full cell width — we use a wrapper trick:
      // outer div = full width for range bg, inner div = circle for start/end
      
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

      let circleCls = "w-12 h-12 flex flex-col items-center justify-center rounded-full transition-all duration-150 relative z-10 "
      if (isStart || isEnd) {
        circleCls += "bg-brand-primary text-white shadow-md scale-105"
      } else if (disabled) {
        circleCls += "opacity-25 cursor-not-allowed text-neutral-400"
      } else if (isHover) {
        circleCls += "bg-brand-primary/10 text-brand-primary cursor-pointer"
      } else {
        circleCls += "hover:bg-neutral-100 cursor-pointer text-neutral-900"
      }

      if (d.iso === today && !isStart && !isEnd) {
        circleCls += " ring-1 ring-inset ring-brand-primary/30"
      }

      const numCls   = `text-sm font-bold leading-none ${isStart || isEnd ? "text-white" : "text-neutral-900"}`
      const priceCls = `text-[9px] font-bold leading-none mt-1 whitespace-nowrap ${
        isStart || isEnd ? "text-white/90" : inRange || isHover ? "text-brand-primary" : "text-brand-primary/80"
      }`

      const priceText = info?.available && info?.min_price != null
        ? this._fmt(info.min_price)
        : (info && !info.available ? "—" : "")

      // Split price to style currency symbol smaller
      let priceHtml = priceText
      if (priceText.includes(" ")) {
        const [sym, amt] = priceText.split(" ")
        priceHtml = `<span class="text-[8px] mr-0.5">${sym}</span>${amt}`
      }

      const actions = disabled ? "" :
        `data-action="click->rate-calendar#pickDay mouseenter->rate-calendar#hoverDay" data-date="${d.iso}"`

      const tooltip = info?.min_price ? `title="${this._fmt(info.min_price)}/night"` : ""

      return `
        <div class="w-12 h-14 flex items-center justify-center relative">
          ${rangeBg ? `<div class="absolute inset-y-1 inset-x-0 ${rangeBg} z-0"></div>` : ""}
          <div class="${circleCls}" ${actions} ${tooltip}>
            <span class="${numCls}">${d.day}</span>
            <span class="${priceCls}">${priceHtml}</span>
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
    const label      = new Date(year, month, 1).toLocaleDateString("en-MY", { month: "long", year: "numeric" })
    const firstDow   = new Date(year, month, 1).getDay()
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

  _isoToday() {
    // Use local date parts to avoid UTC offset shifting the date
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
  }

  _updateDisplay(checkIn, checkOut) {
    if (!this.hasDateDisplayTarget) return
    const fmt = iso => {
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

  async _fetchAround(year, month) {
    if (!this.urlValue) return
    const start    = new Date(year, month, 1)
    const end      = new Date(year, month + 2, 0)
    const startISO = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, "0")}-01`
    const endISO   = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, "0")}-${String(end.getDate()).padStart(2, "0")}`

    // Skip if this range is already fully loaded
    if (this.loadedRanges.some(r => r.from <= startISO && r.to >= endISO)) return

    try {
      const params = new URLSearchParams({
        start_date: startISO,
        end_date: endISO,
        room_count: this.roomCountValue,
        partner_code: this.partnerCodeValue
      })
      const res    = await fetch(`${this.urlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (!res.ok) throw new Error("rate_calendar fetch failed")
      const data = await res.json()
      data.days.forEach(d => this.cache.set(d.date, d))
      this.loadedRanges.push({ from: startISO, to: endISO })
      if (this.open) this._render()
    } catch (e) {
      console.warn("[rate-calendar]", e)
    }
  }

  _fmt(n) {
    const symbols = { MYR: "RM", SGD: "S$", USD: "$", IDR: "Rp" }
    const symbol  = symbols[this.currencyValue] || this.currencyValue
    const amount  = n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n))
    return `${symbol} ${amount}`
  }

  _onOutsideClick = (e) => {
    if (this.open && !this.element.contains(e.target)) this.closePicker()
  }
}
