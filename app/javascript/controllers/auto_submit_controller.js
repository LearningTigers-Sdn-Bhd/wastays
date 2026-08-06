import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 400 }
  }

  connect() {
    this.timeout = null
    this.reenableTimers = []
    this.cleanupBound = this.cleanupEmptyInputs.bind(this)
    this.element.addEventListener("submit", this.cleanupBound)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
    this.reenableTimers.forEach(({ timer, inputs }) => {
      clearTimeout(timer)
      inputs.forEach(input => { input.disabled = false })
    })
    this.reenableTimers = []
    this.element.removeEventListener("submit", this.cleanupBound)
  }

  submit(event) {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    this.timeout = window.setTimeout(() => {
      this.submitNow()
    }, this.delayValue)
  }

  submitNow() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }

    if (typeof this.element.requestSubmit === "function") {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }

  cleanupEmptyInputs(event) {
    const form = this.element
    if (form.getAttribute("method")?.toLowerCase() !== "get") return

    const inputs = Array.from(form.querySelectorAll("input, select, textarea"))
    const disabledInputs = []

    inputs.forEach(input => {
      if (input.name && !input.disabled) {
        const isRadioOrCheckbox = input.type === "radio" || input.type === "checkbox"
        const isEmpty = !input.value || input.value.trim() === ""
        const isActiveElement = input === document.activeElement

        if (!isRadioOrCheckbox && isEmpty && !isActiveElement) {
          input.disabled = true
          disabledInputs.push(input)
        } else if (input.type === "radio" && input.checked && input.value === "") {
          input.disabled = true
          disabledInputs.push(input)
        }
      }
    })

    // Re-enable them immediately in the next event loop tick so they remain usable
    const timer = setTimeout(() => {
      disabledInputs.forEach(input => {
        input.disabled = false
      })
      this.reenableTimers = this.reenableTimers.filter(entry => entry.timer !== timer)
    }, 0)
    this.reenableTimers = [...this.reenableTimers, { timer, inputs: disabledInputs }]
  }
}
