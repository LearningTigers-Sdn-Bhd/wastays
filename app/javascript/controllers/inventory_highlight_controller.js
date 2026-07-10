import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["columnHeader", "rowHeader"]

  highlight(event) {
    const date = event.currentTarget.dataset.date
    const row = event.currentTarget.closest("tr")
    const rowHeader = row.querySelector("[data-inventory-highlight-target='rowHeader']")

    // Clear previous highlights / update all headers' states
    this.columnHeaderTargets.forEach(header => {
      const isActive = header.dataset.columnId === date
      this.updateHeader(header, isActive)
    })

    // Highlight row header (Indigo contrast)
    if (rowHeader) {
      const originalBg = rowHeader.dataset.originalColor || "bg-white"
      originalBg.split(" ").forEach(c => rowHeader.classList.remove(c))
      rowHeader.classList.add("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")

      // Update nested elements with original-color data attribute
      rowHeader.querySelectorAll("[data-original-color]").forEach(el => {
        el.dataset.originalColor.split(" ").forEach(c => el.classList.remove(c))
        const highlightColor = el.dataset.highlightColor || "text-indigo-200"
        highlightColor.split(" ").forEach(c => el.classList.add(c))
      })
    }

    // Highlight the row itself (Prominent indigo highlight)
    row.classList.add("bg-indigo-100")
  }

  clear() {
    this.columnHeaderTargets.forEach(header => {
      this.updateHeader(header, false)
    })

    this.rowHeaderTargets.forEach(header => {
      header.classList.remove("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
      
      // Keep sticky Room/Plan column opaque and restore original background color after hover clears.
      const originalBg = header.dataset.originalColor || "bg-white"
      originalBg.split(" ").forEach(c => header.classList.add(c))

      // Restore nested elements colors
      header.querySelectorAll("[data-original-color]").forEach(el => {
        const highlightColor = el.dataset.highlightColor || "text-indigo-200"
        highlightColor.split(" ").forEach(c => el.classList.remove(c))
        el.dataset.originalColor.split(" ").forEach(c => el.classList.add(c))
      })
    })

    // Clear row highlights
    const tableBody = this.element.querySelector("tbody")
    if (tableBody) {
      tableBody.querySelectorAll("tr").forEach(tr => {
        tr.classList.remove("bg-indigo-100")
      })
    }
  }

  updateHeader(header, isActive) {
    const isWeekend = header.dataset.isWeekend === "true"

    // Reset dynamic classes from header
    header.classList.remove(
      "bg-indigo-600", "bg-indigo-50/60", "bg-indigo-100/70", "bg-slate-50", 
      "text-white", "ring-1", "ring-inset", "ring-indigo-700"
    )

    const dayLabel = header.querySelector("[data-day-label]")
    const numLabel = header.querySelector("[data-num-label]")
    const monthLabel = header.querySelector("[data-month-label]")

    // Helper to reset text classes
    const setTextColor = (el, removeClasses, addClass) => {
      if (!el) return
      removeClasses.forEach(c => el.classList.remove(c))
      if (addClass) el.classList.add(addClass)
    }

    const dayColors = ["text-indigo-200", "text-indigo-400", "text-indigo-600", "text-slate-400"]
    const numColors = ["text-white", "text-indigo-700", "text-slate-700"]
    const monthColors = ["text-indigo-200", "text-white", "text-slate-400"]

    if (isActive) {
      // Hovered (Active) state
      header.classList.add("bg-indigo-600", "text-white", "ring-1", "ring-inset", "ring-indigo-700")
      setTextColor(dayLabel, dayColors, "text-indigo-200")
      setTextColor(numLabel, numColors, "text-white")
      setTextColor(monthLabel, monthColors, "text-white")
    } else {
      // Inactive state
      if (isWeekend) {
        header.classList.add("bg-indigo-100/70")
        setTextColor(dayLabel, dayColors, "text-indigo-600")
        setTextColor(numLabel, numColors, "text-indigo-700")
      } else {
        header.classList.add("bg-slate-50")
        setTextColor(dayLabel, dayColors, "text-slate-400")
        setTextColor(numLabel, numColors, "text-slate-700")
      }
      setTextColor(monthLabel, monthColors, "text-slate-400")
    }
  }
}
