import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["popover", "display", "input", "hour", "minute", "period"]

  connect() {
    this.closeHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
    
    // Initialize display if input has value
    if (this.inputTarget.value) {
      this.updateDisplayFromInput()
    }
  }

  toggle() {
    if (this.popoverTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.popoverTarget.classList.remove("hidden")
    document.addEventListener("click", this.closeHandler)
    
    // Ensure something is selected when opened if nothing is selected
    this.ensureDefaults()
  }

  close() {
    this.popoverTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeHandler)
  }

  ensureDefaults() {
    const hasHour = Array.from(this.hourTargets).some(el => el.classList.contains("bg-blue-600"))
    if (!hasHour && this.hourTargets.length > 0) {
      this.hourTargets[11].classList.add("bg-blue-600", "text-white") // Default to 12
    }

    const hasMinute = Array.from(this.minuteTargets).some(el => el.classList.contains("bg-blue-600"))
    if (!hasMinute && this.minuteTargets.length > 0) {
      this.minuteTargets[0].classList.add("bg-blue-600", "text-white") // Default to 00
    }

    const hasPeriod = Array.from(this.periodTargets).some(el => el.classList.contains("bg-blue-600"))
    if (!hasPeriod && this.periodTargets.length > 0) {
      this.periodTargets[0].classList.add("bg-blue-600", "text-white") // Default to AM
    }
  }

  selectHour(event) {
    this.hourTargets.forEach(el => el.classList.remove("bg-blue-600", "text-white"))
    event.currentTarget.classList.add("bg-blue-600", "text-white")
  }

  selectMinute(event) {
    this.minuteTargets.forEach(el => el.classList.remove("bg-blue-600", "text-white"))
    event.currentTarget.classList.add("bg-blue-600", "text-white")
  }

  selectPeriod(event) {
    this.periodTargets.forEach(el => el.classList.remove("bg-blue-600", "text-white"))
    event.currentTarget.classList.add("bg-blue-600", "text-white")
  }

  confirm(event) {
    if (event) event.preventDefault()
    this.updateValue()
    this.close()
  }

  updateValue() {
    const selectedHour = Array.from(this.hourTargets).find(el => el.classList.contains("bg-blue-600"))
    const selectedMinute = Array.from(this.minuteTargets).find(el => el.classList.contains("bg-blue-600"))
    const selectedPeriod = Array.from(this.periodTargets).find(el => el.classList.contains("bg-blue-600"))

    const hour = selectedHour ? selectedHour.dataset.value : "12"
    const minute = selectedMinute ? selectedMinute.dataset.value : "00"
    const period = selectedPeriod ? selectedPeriod.dataset.value : "AM"

    const timeString = `${hour}:${minute} ${period}`
    
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = timeString
      this.displayTarget.classList.remove("text-neutral-text-secondary")
      this.displayTarget.classList.add("text-neutral-text-primary")
    }
    
    if (this.hasInputTarget) {
      // Convert to 24h for the hidden input
      let h = parseInt(hour)
      if (period === "PM" && h < 12) h += 12
      if (period === "AM" && h === 12) h = 0
      
      const formattedTime = `${h.toString().padStart(2, '0')}:${minute}`
      this.inputTarget.value = formattedTime
    }
  }

  updateDisplayFromInput() {
    if (!this.inputTarget.value) return

    const [h24, m] = this.inputTarget.value.split(":")
    let h = parseInt(h24)
    let p = "AM"
    
    if (h >= 12) {
      p = "PM"
      if (h > 12) h -= 12
    }
    if (h === 0) h = 12
    
    const hour = h.toString()
    const minute = m

    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = `${hour}:${minute} ${p}`
      this.displayTarget.classList.remove("text-neutral-text-secondary")
      this.displayTarget.classList.add("text-neutral-text-primary")
    }
    
    // Update active states in UI
    this.hourTargets.forEach(el => {
      if (el.dataset.value === hour) el.classList.add("bg-blue-600", "text-white")
      else el.classList.remove("bg-blue-600", "text-white")
    })
    
    this.minuteTargets.forEach(el => {
      if (el.dataset.value === minute) el.classList.add("bg-blue-600", "text-white")
      else el.classList.remove("bg-blue-600", "text-white")
    })

    this.periodTargets.forEach(el => {
      if (el.dataset.value === p) el.classList.add("bg-blue-600", "text-white")
      else el.classList.remove("bg-blue-600", "text-white")
    })
  }
}
