import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropdown", "hour", "minute", "hiddenInput"]
  static values = { 
    nextFieldSelector: String,
    currentHour: Number,
    currentMinute: Number
  }

  connect() {
    this.close()
    this.parseInitialValue()
  }

  toggle() {
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
    this.highlightCurrent()
    document.addEventListener("click", this.handleOutsideClick.bind(this))
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.handleOutsideClick.bind(this))
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  selectHour(event) {
    this.currentHourValue = parseInt(event.currentTarget.dataset.value)
    this.highlightCurrent()
    this.updateDisplay()
  }

  selectMinute(event) {
    this.currentMinuteValue = parseInt(event.currentTarget.dataset.value)
    this.highlightCurrent()
    this.updateDisplay()
    this.close()
    this.advance()
  }

  updateDisplay() {
    const formatted = this.formatTime(this.currentHourValue, this.currentMinuteValue)
    this.inputTarget.value = formatted
    this.hiddenInputTarget.value = formatted
    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  highlightCurrent() {
    this.hourTargets.forEach(el => {
      const active = parseInt(el.dataset.value) === this.currentHourValue
      el.classList.toggle("bg-slate-900", active)
      el.classList.toggle("text-white", active)
      el.classList.toggle("bg-white", !active)
      el.classList.toggle("text-slate-700", !active)
    })

    this.minuteTargets.forEach(el => {
      const active = parseInt(el.dataset.value) === this.currentMinuteValue
      el.classList.toggle("bg-slate-900", active)
      el.classList.toggle("text-white", active)
      el.classList.toggle("bg-white", !active)
      el.classList.toggle("text-slate-700", !active)
    })
  }

  formatTime(h, m) {
    const period = h >= 12 ? "PM" : "AM"
    let h12 = h % 12
    if (h12 === 0) h12 = 12
    const mm = m.toString().padStart(2, '0')
    return `${h12}:${mm} ${period}`
  }

  parseInitialValue() {
    const value = this.hiddenInputTarget.value
    if (!value) {
      this.currentHourValue = 14
      this.currentMinuteValue = 0
      return
    }

    const match = value.match(/(\d+):(\d+)\s*(AM|PM)/i)
    if (match) {
      let h = parseInt(match[1])
      const m = parseInt(match[2])
      const p = match[3].toUpperCase()
      if (p === "PM" && h < 12) h += 12
      if (p === "AM" && h === 12) h = 0
      this.currentHourValue = h
      this.currentMinuteValue = m
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
