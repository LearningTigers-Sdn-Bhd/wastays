import { Controller } from "@hotwired/stimulus"

// Collapses the rows of one room-type group.
//
// A table has a single <tbody>, so a group is not a DOM subtree this could wrap:
// the header row's button and the rows it controls are siblings. The button
// therefore owns aria-expanded and names its group, and this controller — which
// sits on the table — resolves that group's rows by their data-group key.
export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget
    const group = event.params.group
    const collapsing = button.getAttribute("aria-expanded") === "true"

    button.setAttribute("aria-expanded", String(!collapsing))
    button.querySelector("[data-table-group-target='icon']")?.classList.toggle("rotate-90", !collapsing)

    this.element.querySelectorAll(`[data-group="${group}"]`).forEach(row => {
      row.hidden = collapsing
    })
  }
}
