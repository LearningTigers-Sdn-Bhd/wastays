import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "popover", "hour", "minute", "period", "hiddenInput", "display"]
  static values = { 
    nextFieldSelector: String
  }

  connect() {
    this.currentHour = undefined
    this.currentMinute = undefined
    
    this.close()
    this.parseInitialValue()
    
    this.closeHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  toggle() {
    const isHidden = this.containerTarget.classList.contains("hidden")

    if (isHidden) {
      this.open()
    } else {
      this.close()
    }
  }

  get containerTarget() {
    return this.hasDropdownTarget ? this.dropdownTarget : this.popoverTarget
  }

  open() {
    this.containerTarget.classList.remove("hidden")
    this.highlightCurrent()
    this.scrollToSelected()
    document.addEventListener("click", this.closeHandler)
  }

  scrollToSelected() {
    if (this.currentHour === undefined || this.currentMinute === undefined) return

    const activeHour = this.hourTargets.find(el => el.classList.contains("bg-blue-600") || el.classList.contains("bg-slate-900"))
    const activeMinute = this.minuteTargets.find(el => el.classList.contains("bg-blue-600") || el.classList.contains("bg-slate-900"))

    if (activeHour) activeHour.scrollIntoView({ block: "nearest", behavior: "smooth" })
    if (activeMinute) activeMinute.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  close() {
    this.containerTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeHandler)
  }

  selectHour(event) {
    const val = event.currentTarget.dataset.value
    const h = parseInt(val)
    
    if (this.hasPeriodTarget) {
      // In 12h mode, preserve PM if already set
      const isPM = this.currentHour !== undefined && this.currentHour >= 12
      let newH24 = h % 12
      if (isPM) newH24 += 12
      else if (h === 12) newH24 = 0 // 12 AM is 0
      this.currentHour = newH24
    } else {
      this.currentHour = h
    }

    this.updateDisplay()
    this.highlightCurrent()
    this.checkAutoClose()
  }

  selectMinute(event) {
    const val = event.currentTarget.dataset.value
    this.currentMinute = parseInt(val)
    
    this.updateDisplay()
    this.highlightCurrent()
    this.checkAutoClose()
  }

  selectPeriod(event) {
    const period = event.currentTarget.dataset.value
    const isPM = period === "PM"
    
    // Default to 12 if no hour selected yet
    let currentH12 = this.currentHour !== undefined ? (this.currentHour % 12) : 12
    if (currentH12 === 0) currentH12 = 12
    
    let newH24 = currentH12
    if (isPM && currentH12 < 12) newH24 += 12
    if (!isPM && currentH12 === 12) newH24 = 0
    
    this.currentHour = newH24
    
    this.updateDisplay()
    this.highlightCurrent()
    this.checkAutoClose()
  }

  checkAutoClose() {
    if (this.currentHour !== undefined && this.currentMinute !== undefined) {
      if (!this.hasPeriodTarget || this.hasSelectedPeriod()) {
        this.close()
        this.advance()
      }
    }
  }

  hasSelectedPeriod() {
    if (!this.hasPeriodTarget) return true
    // If we parsed an initial value or clicked a period, we consider it "selected"
    // Since we default to AM/PM on selectHour, we look for an explicit click or existing state
    return true // For the simplified 3-column UI, we want it to feel live
  }

  updateDisplay() {
    const h = this.currentHour ?? 12
    const m = this.currentMinute ?? 0
    const formatted = this.formatTime(h, m)
    
    if (this.hasInputTarget) {
      this.inputTarget.value = formatted
    }

    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = formatted
      this.displayTarget.classList.remove("text-neutral-text-secondary")
      this.displayTarget.classList.add("text-neutral-text-primary")
    }

    if (this.hasHiddenInputTarget) {
      const h24 = h.toString().padStart(2, '0')
      const m24 = m.toString().padStart(2, '0')
      this.hiddenInputTarget.value = `${h24}:${m24}`
      this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  highlightCurrent() {
    if (this.currentHour === undefined && this.currentMinute === undefined) {
      this.hourTargets.forEach(el => this.applyClasses(el, false))
      this.minuteTargets.forEach(el => this.applyClasses(el, false))
      if (this.hasPeriodTarget) this.periodTargets.forEach(el => this.applyClasses(el, false))
      return
    }

    const h24 = this.currentHour ?? -1
    const m = this.currentMinute ?? -1
    
    if (this.hasPeriodTarget) {
      let h12 = h24 % 12
      if (h12 === 0) h12 = 12
      const p = h24 >= 12 ? "PM" : "AM"
      
      this.hourTargets.forEach(el => {
        const active = this.currentHour !== undefined && parseInt(el.dataset.value) === h12
        this.applyClasses(el, active)
      })
      
      this.minuteTargets.forEach(el => {
        const active = this.currentMinute !== undefined && parseInt(el.dataset.value) === m
        this.applyClasses(el, active)
      })
      
      this.periodTargets.forEach(el => {
        const active = this.currentHour !== undefined && el.dataset.value === p
        this.applyClasses(el, active)
      })
    } else {
      this.hourTargets.forEach(el => {
        const active = this.currentHour !== undefined && parseInt(el.dataset.value) === h24
        this.applyClasses(el, active)
      })

      this.minuteTargets.forEach(el => {
        const active = this.currentMinute !== undefined && parseInt(el.dataset.value) === m
        this.applyClasses(el, active)
      })
    }
  }

  applyClasses(el, active) {
    el.classList.toggle("bg-slate-900", active)
    el.classList.toggle("text-white", active)
    el.classList.toggle("bg-white", !active)
    el.classList.toggle("text-slate-700", !active)
  }

  formatTime(h, m) {
    const period = h >= 12 ? "PM" : "AM"
    let h12 = h % 12
    if (h12 === 0) h12 = 12
    const mm = m.toString().padStart(2, '0')
    return `${h12}:${mm} ${period}`
  }

  parseInitialValue() {
    let value = ""
    if (this.hasHiddenInputTarget) value = this.hiddenInputTarget.value
    else if (this.hasInputTarget) value = this.inputTarget.value
    
    if (!value) return

    // Try to parse HH:mm (24h) or h:mm AM/PM
    const match12 = value.match(/(\d+):(\d+)\s*(AM|PM)/i)
    if (match12) {
      let h = parseInt(match12[1])
      const m = parseInt(match12[2])
      const p = match12[3].toUpperCase()
      if (p === "PM" && h < 12) h += 12
      if (p === "AM" && h === 12) h = 0
      this.currentHourValue = h
      this.currentMinuteValue = m
    } else {
      const match24 = value.match(/(\d+):(\d+)/)
      if (match24) {
        this.currentHourValue = parseInt(match24[1])
        this.currentMinuteValue = parseInt(match24[2])
      }
    }
  }

  advance() {
    if (this.hasNextFieldSelectorValue) {
      setTimeout(() => {
        const nextElement = document.querySelector(this.nextFieldSelectorValue)
        if (nextElement) {
          const nextInput = nextElement.querySelector('input') || nextElement
          nextInput.focus()
          nextInput.click()
        }
      }, 150)
    }
  }
}
