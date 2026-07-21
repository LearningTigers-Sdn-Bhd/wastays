import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inList", "outList"]

  addInRow() {
    this.appendRow(this.inListTarget, "hotel[boat_in_times][]")
  }

  addOutRow() {
    this.appendRow(this.outListTarget, "hotel[boat_out_times][]")
  }

  appendRow(list, name) {
    const div = document.createElement("div")
    div.className = "flex items-center gap-2"
    div.innerHTML = `
      <input type="time" name="${name}" class="rounded-md border border-border bg-background px-3 py-2 text-sm font-medium text-foreground focus:border-border-interactive focus:ring-0 shadow-sm w-36" required>
      <button type="button" data-action="click->boat-schedules#removeRow" class="text-xs font-semibold text-destructive hover:text-destructive p-2">Remove</button>
    `
    list.appendChild(div)
  }

  removeRow(event) {
    event.target.closest("div").remove()
  }
}
