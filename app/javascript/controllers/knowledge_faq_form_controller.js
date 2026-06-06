import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  connect() {
    this.counter = this.containerTarget.children.length
  }

  add() {
    const content = this.templateTarget.content.cloneNode(true)
    const index = this.counter

    content.querySelectorAll("input, textarea").forEach((el) => {
      el.name = el.name.replace("__INDEX__", index)
      el.id = el.id.replace("__INDEX__", index)
    })

    this.containerTarget.appendChild(content)
    this.counter++
  }

  remove(event) {
    const row = event.target.closest("[data-qa-pair]")
    if (row) {
      row.remove()
      this.reindex()
    }
  }

  reindex() {
    const rows = this.containerTarget.querySelectorAll("[data-qa-pair]")
    rows.forEach((row, i) => {
      row.querySelectorAll("input, textarea").forEach((el) => {
        el.name = el.name.replace(/\[\d+\]/, `[${i}]`)
        el.id = el.id.replace(/_\d+_/, `_${i}_`)
      })
    })
    this.counter = rows.length
  }
}
