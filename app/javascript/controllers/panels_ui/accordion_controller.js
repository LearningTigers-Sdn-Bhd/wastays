import { Controller } from "@hotwired/stimulus"

// Coordinates direct Collapsible children as one WAI-ARIA accordion.
export default class extends Controller {
  static values = {
    type: { type: String, default: "single" },
    collapsible: { type: Boolean, default: false }
  }

  connect() {
    this.syncLockedTrigger()
  }

  itemChanged(event) {
    if (!this.owns(event.target) || this.coordinating) return

    const item = event.target
    const open = event.detail.open

    if (this.typeValue === "single" && open) {
      this.coordinating = true
      this.items.filter((candidate) => candidate !== item).forEach((candidate) => {
        this.collapsible(candidate)?.close()
      })
      this.coordinating = false
    } else if (this.typeValue === "single" && !this.collapsibleValue && !this.openItem) {
      this.collapsible(item)?.open()
    }

    this.syncLockedTrigger()
    this.dispatch("change", {
      detail: { value: item.dataset.accordionValue, open, values: this.openValues }
    })
  }

  navigate(event) {
    if (!this.owns(event.target) || !event.target.matches("[data-accordion-trigger]")) return

    const triggers = this.enabledTriggers
    const current = triggers.indexOf(event.target)
    if (current < 0) return

    let index
    if (event.key === "Home") index = 0
    if (event.key === "End") index = triggers.length - 1
    if (event.key === "ArrowDown") index = (current + 1) % triggers.length
    if (event.key === "ArrowUp") index = (current - 1 + triggers.length) % triggers.length
    if (index === undefined) return

    event.preventDefault()
    triggers[index]?.focus()
  }

  syncLockedTrigger() {
    if (this.typeValue !== "single" || this.collapsibleValue) {
      this.triggers.forEach((trigger) => trigger.removeAttribute("aria-disabled"))
      return
    }

    this.triggers.forEach((trigger) => {
      if (trigger.getAttribute("aria-expanded") === "true") {
        trigger.setAttribute("aria-disabled", "true")
      } else {
        trigger.removeAttribute("aria-disabled")
      }
    })
  }

  owns(element) {
    return element.closest('[data-controller~="panels-ui--accordion"]') === this.element
  }

  collapsible(item) {
    return this.application.getControllerForElementAndIdentifier(item, "panels-ui--collapsible")
  }

  get items() {
    return Array.from(this.element.children).filter((child) => child.matches("[data-accordion-item]"))
  }

  get triggers() {
    return this.items.map((item) => item.querySelector("[data-accordion-trigger]"))
  }

  get enabledTriggers() {
    return this.triggers.filter((trigger) => trigger && !trigger.disabled)
  }

  get openItem() {
    return this.items.find((item) => item.dataset.state === "open")
  }

  get openValues() {
    return this.items.filter((item) => item.dataset.state === "open").map((item) => item.dataset.accordionValue)
  }
}
