import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "input"]

  toggle(event) {
    const item = event.currentTarget
    if (item.disabled) return

    const pressed = item.getAttribute("aria-pressed") === "true"
    if (pressed && this.required && this.selectedItems.length === 1) return

    if (this.type === "single" && !pressed) {
      this.itemTargets.forEach((candidate) => this.setPressed(candidate, candidate === item))
    } else {
      this.setPressed(item, !pressed)
    }

    this.makeTabbable(item)
    const changedInput = this.syncInputs(item.dataset.value)
    this.dispatchNativeEvents(changedInput)
    this.dispatch("change", {
      detail: {
        type: this.type,
        value: this.value,
        item,
        inputs: this.hasInputTarget ? this.inputTargets : []
      }
    })
  }

  onKeydown(event) {
    if (!this.itemTargets.includes(event.target)) return

    const items = this.enabledItems
    if (items.length === 0) return

    let index
    if (event.key === "Home") {
      index = 0
    } else if (event.key === "End") {
      index = items.length - 1
    } else {
      const step = this.stepFor(event.key)
      if (!step) return

      const current = items.indexOf(event.target)
      index = (current + step + items.length) % items.length
    }

    event.preventDefault()
    this.makeTabbable(items[index])
    items[index].focus()
  }

  setPressed(item, pressed) {
    item.setAttribute("aria-pressed", pressed.toString())
    item.dataset.state = pressed ? "on" : "off"
  }

  makeTabbable(item) {
    this.itemTargets.forEach((candidate) => {
      candidate.tabIndex = candidate === item ? 0 : -1
    })
  }

  syncInputs(changedValue) {
    if (!this.hasInputTarget) return null

    if (this.type === "single") {
      this.inputTarget.value = this.selectedItems[0]?.dataset.value || ""
      return this.inputTarget
    }

    this.inputTargets.forEach((input) => {
      input.disabled = !this.selectedItems.some((item) => item.dataset.value === input.dataset.value)
    })
    return this.inputTargets.find((input) => input.dataset.value === changedValue) || this.inputTargets[0]
  }

  dispatchNativeEvents(input) {
    if (!input) return

    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  stepFor(key) {
    if (this.orientation === "vertical") return { ArrowDown: 1, ArrowUp: -1 }[key]

    const direction = getComputedStyle(this.element).direction === "rtl" ? -1 : 1
    return { ArrowRight: direction, ArrowLeft: -direction }[key]
  }

  get type() { return this.element.dataset.type }
  get orientation() { return this.element.dataset.orientation }
  get required() { return this.element.dataset.required === "true" }
  get enabledItems() { return this.itemTargets.filter((item) => !item.disabled) }
  get selectedItems() { return this.itemTargets.filter((item) => item.getAttribute("aria-pressed") === "true") }

  get value() {
    const values = this.selectedItems.map((item) => item.dataset.value)
    return this.type === "multiple" ? values : (values[0] || null)
  }
}
