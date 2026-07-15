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
      <input type="time" name="${name}" class="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-900 focus:border-slate-300 focus:ring-0 shadow-sm w-36" required>
      <button type="button" data-action="click->boat-schedules#removeRow" class="text-xs text-red-600 hover:text-red-800 font-semibold p-2">Remove</button>
    `
    list.appendChild(div)
  }

  removeRow(event) {
    event.target.closest("div").remove()
  }
}
