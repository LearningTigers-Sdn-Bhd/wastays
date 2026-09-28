import { Controller } from "@hotwired/stimulus"

// Subdivides "How should this room be priced?" into one question at a time
// instead of showing every field for a mode at once. It only sequences steps;
// rate_plan_room_pricing_controller (on the same ancestor) still decides which
// mode's panel is visible and computes the live preview — a hidden ancestor
// panel keeps this controller's steps hidden regardless of their own state.
//
// A numbered progress list (built from each step's data-wizard-title) makes it
// obvious up front that this is a short step-by-step form; completed steps in
// it are buttons, so any earlier answer is one click away.
export default class extends Controller {
  static targets = [ "step", "back", "continueButton", "doneHint", "progress", "modeLabel" ]
  static values = { step: { type: Number, default: 1 }, mode: String }

  connect() {
    this.render()
  }

  // Picking a mode is itself the answer to step 1 — move straight to its first
  // question. Bound to click (not change) so re-picking the already-selected
  // card also moves on instead of appearing to do nothing.
  selectMode(event) {
    this.modeValue = event.target.value
    this.stepValue = 2
  }

  continue() {
    this.stepValue += 1
  }

  back() {
    this.stepValue = Math.max(1, this.stepValue - 1)
  }

  goTo(event) {
    this.stepValue = Number(event.currentTarget.dataset.wizardStep)
  }

  modeValueChanged() {
    this.render()
  }

  stepValueChanged() {
    this.render()
  }

  stepsForCurrentMode() {
    return this.stepTargets.filter((step) => !step.dataset.wizardMode || step.dataset.wizardMode === this.modeValue)
  }

  render() {
    const steps = this.stepsForCurrentMode()
    const maxStep = Math.max(1, ...steps.map((step) => Number(step.dataset.wizardStep)))
    const current = Math.min(Math.max(this.stepValue, 1), maxStep)

    this.stepTargets.forEach((step) => {
      const relevant = !step.dataset.wizardMode || step.dataset.wizardMode === this.modeValue
      const isCurrent = relevant && Number(step.dataset.wizardStep) === current
      step.classList.toggle("hidden", !isCurrent)
    })

    // Nav stays visible even at step 1: a mode may already be selected (its
    // radio pre-checked, e.g. editing an existing plan, or "manual" being the
    // default for a brand-new one), so Continue is always a way forward.
    if (this.hasBackTarget) this.backTarget.classList.toggle("invisible", current <= 1)
    if (this.hasContinueButtonTarget) this.continueButtonTarget.classList.toggle("hidden", current >= maxStep)
    if (this.hasDoneHintTarget) this.doneHintTarget.classList.toggle("hidden", current < maxStep)
    this.renderProgress(steps, current)
  }

  renderProgress(steps, current) {
    if (!this.hasProgressTarget) return

    const items = steps
      .sort((a, b) => Number(a.dataset.wizardStep) - Number(b.dataset.wizardStep))
      .map((step) => this.progressItem(step, current))
    this.progressTarget.replaceChildren(...items)
  }

  progressItem(step, current) {
    const number = Number(step.dataset.wizardStep)
    const state = number < current ? "done" : (number === current ? "current" : "upcoming")
    const title = number === 1 && state === "done" ? this.selectedModeLabel() || step.dataset.wizardTitle : step.dataset.wizardTitle

    const item = document.createElement("li")
    item.className = "flex items-center gap-2"
    if (state === "current") item.setAttribute("aria-current", "step")

    const badge = document.createElement("span")
    badge.className = [
      "inline-flex size-5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold tabular-nums",
      state === "upcoming" ? "border border-border text-muted-foreground" : "bg-foreground text-background"
    ].join(" ")
    badge.textContent = number
    badge.setAttribute("aria-hidden", "true")

    const label = document.createElement(state === "done" ? "button" : "span")
    label.textContent = title
    label.className = [
      "text-xs",
      state === "current" ? "font-semibold text-foreground" : "text-muted-foreground",
      state === "done" ? "underline-offset-2 hover:text-foreground hover:underline" : ""
    ].join(" ")
    if (state === "done") {
      label.type = "button"
      label.dataset.wizardStep = number
      label.dataset.action = "click->rate-plan-pricing-wizard#goTo"
      label.setAttribute("aria-label", `Step ${number}: ${title} (go back to this step)`)
    }

    item.append(badge, label)
    return item
  }

  selectedModeLabel() {
    const checked = this.element.querySelector("input[type='radio'][data-wizard-mode-label]:checked")
    return checked?.dataset.wizardModeLabel
  }
}
