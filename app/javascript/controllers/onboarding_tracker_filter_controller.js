import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "empty", "search", "startDate", "endDate"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const startDate = this.hasStartDateTarget ? this.startDateTarget.value : ""
    const endDate = this.hasEndDateTarget ? this.endDateTarget.value : ""

    let visibleRows = 0

    this.rowTargets.forEach((row) => {
      const searchText = (row.dataset.searchText || "").toLowerCase()
      const scheduledDates = (row.dataset.scheduledDates || "").split("|").filter(Boolean)

      const matchesSearch = query === "" || searchText.includes(query)
      const matchesDateRange = this.matchesDateRange(scheduledDates, startDate, endDate)
      const visible = matchesSearch && matchesDateRange

      row.classList.toggle("hidden", !visible)

      if (visible) {
        visibleRows += 1
      }
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visibleRows > 0)
    }
  }

  clear(event) {
    event?.preventDefault()

    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
    }

    if (this.hasStartDateTarget) {
      this.startDateTarget.value = ""
    }

    if (this.hasEndDateTarget) {
      this.endDateTarget.value = ""
    }

    this.filter()

    if (this.hasSearchTarget) {
      this.searchTarget.focus()
    }
  }

  matchesDateRange(scheduledDates, startDate, endDate) {
    if (!startDate && !endDate) {
      return true
    }

    if (scheduledDates.length === 0) {
      return false
    }

    return scheduledDates.some((date) => {
      const matchesStart = !startDate || date >= startDate
      const matchesEnd = !endDate || date <= endDate

      return matchesStart && matchesEnd
    })
  }
}
