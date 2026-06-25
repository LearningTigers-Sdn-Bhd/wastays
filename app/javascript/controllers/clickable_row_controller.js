import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  visit(event) {
    if (this.interactiveTarget(event.target)) return

    Turbo.visit(this.urlValue)
  }

  visitFromKeyboard(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    if (this.interactiveTarget(event.target)) return

    event.preventDefault()
    Turbo.visit(this.urlValue)
  }

  interactiveTarget(target) {
    const element = target instanceof Element ? target : target?.parentElement

    return element?.closest("a, button, input, select, textarea, label, [role='menu'], [role='menuitem']")
  }
}
