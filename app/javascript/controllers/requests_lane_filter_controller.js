import { Controller } from "@hotwired/stimulus"

// Keeps the synthetic "All" choice mutually exclusive with specific request
// lanes, then submits the GET form once the ToggleGroup's hidden inputs match
// what its buttons show.
export default class extends Controller {
  change(event) {
    const changedItem = event.detail.item
    const allItem = this.itemFor("all")
    const specificItems = this.items.filter((item) => item !== allItem)

    if (changedItem === allItem) {
      this.setPressed(allItem, true)
      specificItems.forEach((item) => this.setPressed(item, false))
    } else {
      this.setPressed(allItem, false)
      if (!specificItems.some((item) => this.pressed(item))) this.setPressed(allItem, true)
    }

    this.syncInputs()
    this.submit()
  }

  setPressed(item, pressed) {
    if (!item) return

    item.setAttribute("aria-pressed", pressed.toString())
    item.dataset.state = pressed ? "on" : "off"
  }

  syncInputs() {
    const selectedValues = this.items.filter((item) => this.pressed(item)).map((item) => item.dataset.value)

    this.inputs.forEach((input) => {
      if (input.dataset.value) input.disabled = !selectedValues.includes(input.dataset.value)
    })
  }

  submit() {
    const form = this.element.closest("form")
    if (!form) return

    const autoSubmit = this.application.getControllerForElementAndIdentifier(form, "auto-submit")
    if (autoSubmit) {
      autoSubmit.submitNow()
    } else if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  itemFor(value) {
    return this.items.find((item) => item.dataset.value === value)
  }

  pressed(item) {
    return item?.getAttribute("aria-pressed") === "true"
  }

  get items() {
    return Array.from(this.element.querySelectorAll('[data-slot="toggle-group-item"]'))
  }

  get inputs() {
    return Array.from(this.element.querySelectorAll('[data-panels-ui--toggle-group-target="input"]'))
  }
}
