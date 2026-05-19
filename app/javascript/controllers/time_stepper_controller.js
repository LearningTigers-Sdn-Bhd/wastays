import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { nextFieldSelector: String }

  connect() {
    this.formatInput()
  }

  stepHour(event) {
    const delta = parseInt(event.currentTarget.dataset.delta)
    this.adjustTime(delta, 0)
  }

  stepMinute(event) {
    const delta = parseInt(event.currentTarget.dataset.delta)
    this.adjustTime(0, delta)
  }

  adjustTime(hours, minutes) {
    let [h, m] = this.parseTime(this.inputTarget.value)
    
    h = (h + hours + 24) % 24
    m = (m + minutes + 60) % 60
    
    this.setTime(h, m)
  }

  setPreset(event) {
    const [h, m] = this.parseTime(event.currentTarget.dataset.time)
    this.setTime(h, m)
    
    // Auto-advance logic
    if (this.hasNextFieldSelectorValue) {
      setTimeout(() => {
        const nextElement = document.querySelector(this.nextFieldSelectorValue)
        if (nextElement) {
          const nextInput = nextElement.querySelector('input') || nextElement
          nextInput.focus()
          nextInput.click()
        }
      }, 200)
    }
  }

  setTime(h, m) {
    const formatted = this.formatHHMM(h, m)
    this.inputTarget.value = formatted
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  parseTime(value) {
    if (!value) return [14, 0] 
    
    if (value.includes("M")) {
      const match = value.match(/(\d+):(\d+)\s*(AM|PM)/i)
      if (match) {
        let hours = parseInt(match[1])
        const mins = parseInt(match[2])
        const period = match[3].toUpperCase()
        
        if (period === "PM" && hours < 12) hours += 12
        if (period === "AM" && hours === 12) hours = 0
        return [hours, mins]
      }
    }

    const parts = value.split(":")
    if (parts.length === 2) {
      return [parseInt(parts[0]), parseInt(parts[1])]
    }

    return [14, 0]
  }

  formatHHMM(h, m) {
    const period = h >= 12 ? "PM" : "AM"
    let h12 = h % 12
    if (h12 === 0) h12 = 12
    
    return `${h12}:${m.toString().padStart(2, '0')} ${period}`
  }

  formatInput() {
    const [h, m] = this.parseTime(this.inputTarget.value)
    this.inputTarget.value = this.formatHHMM(h, m)
  }
}
