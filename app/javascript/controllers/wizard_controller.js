import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "step",
    "progressDot",
    "progressCheck",
    "progressNumber",
    "progressLine",
    "backButton",
    "nextButton",
    "submitButton",
    "terms"
  ]
  static values = { current: { type: Number, default: 1 } }

  connect() {
    this.showStep(this.currentValue)
  }

  next() {
    if (!this.currentStepIsValid()) return
    if (this.currentValue < this.stepTargets.length) {
      this.currentValue += 1
      this.showStep(this.currentValue)
    }
  }

  back() {
    if (this.currentValue > 1) {
      this.currentValue -= 1
      this.showStep(this.currentValue)
    }
  }

  handleSubmit(event) {
    if (this.currentValue < this.stepTargets.length) {
      event.preventDefault()
      this.next()
    }
  }

  currentStepIsValid() {
    const step = this.stepTargets[this.currentValue - 1]
    const fields = step.querySelectorAll("input, select, textarea")

    for (const field of fields) {
      if (!field.reportValidity()) return false
    }

    return true
  }

  showStep(stepNumber) {
    this.stepTargets.forEach((step, index) => {
      step.classList.toggle("hidden", index !== stepNumber - 1)
    })

    this.progressDotTargets.forEach((dot, index) => {
      const num = index + 1
      const done = num < stepNumber
      const active = num === stepNumber

      dot.classList.toggle("bg-[#1e2e2a]", done || active)
      dot.classList.toggle("bg-border", !done && !active)

      if (this.hasProgressNumberTarget) {
        const numberEl = this.progressNumberTargets[index]
        const checkEl = this.progressCheckTargets[index]
        numberEl.classList.toggle("hidden", done)
        checkEl.classList.toggle("hidden", !done)
        numberEl.classList.toggle("text-[#d9c5a0]", active)
        numberEl.classList.toggle("text-muted-foreground", !active)
      }
    })

    this.progressLineTargets.forEach((line, index) => {
      line.classList.toggle("bg-[#1e2e2a]", index + 1 < stepNumber)
      line.classList.toggle("bg-border", index + 1 >= stepNumber)
    })

    const isLastStep = stepNumber === this.stepTargets.length

    this.backButtonTarget.style.display = stepNumber === 1 ? "none" : ""
    this.nextButtonTarget.style.display = isLastStep ? "none" : ""
    this.submitButtonTarget.style.display = isLastStep ? "" : "none"

    if (this.hasTermsTarget) this.termsTarget.style.display = isLastStep ? "" : "none"
  }
}
