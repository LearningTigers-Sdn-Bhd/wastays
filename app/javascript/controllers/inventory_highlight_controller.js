import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["columnHeader", "rowHeader", "rowLabel"]

  highlight(event) {
    const date = event.currentTarget.dataset.date
    const row = event.currentTarget.closest("tr")
    const rowHeader = row.querySelector("[data-inventory-highlight-target='rowHeader']")
    const rowLabel = row.querySelector("[data-inventory-highlight-target='rowLabel']")

    // Clear previous highlights
    this.clear()

    // Highlight column header (Indigo contrast)
    this.columnHeaderTargets.forEach(header => {
      if (header.dataset.columnId === date) {
        header.classList.add("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
        header.querySelectorAll("span").forEach(s => s.classList.add("text-white"))
      }
    })

    // Highlight row header (Indigo contrast)
    if (rowHeader) {
      rowHeader.classList.add("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
    }

    // Highlight row label
    if (rowLabel) {
      rowLabel.classList.add("text-slate-900", "font-black")
      rowLabel.classList.remove("text-slate-950", "text-slate-600")
    }

    // Highlight the row itself (Subtle indigo wash)
    row.classList.add("bg-indigo-50/50")
  }

  clear() {
    this.columnHeaderTargets.forEach(header => {
      header.classList.remove("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
      header.querySelectorAll("span").forEach(s => s.classList.remove("text-white"))
    })

    this.rowHeaderTargets.forEach(header => {
      header.classList.remove("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
      // Keep sticky Room/Plan column opaque after hover clears.
      header.classList.add("bg-white")
    })

    this.rowLabelTargets.forEach(label => {
      label.classList.remove("font-black")
      // Restore standard colors
      if (label.classList.contains("ms-5")) { // Rate plan label
        label.classList.add("text-slate-600")
      } else {
        label.classList.add("text-slate-950")
      }
    })

    // Clear row highlights
    const tableBody = this.element.querySelector("tbody")
    if (tableBody) {
      tableBody.querySelectorAll("tr").forEach(tr => {
        tr.classList.remove("bg-indigo-50/50")
      })
    }
  }
}
