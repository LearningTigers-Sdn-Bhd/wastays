import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "empty", "search", "sort", "startDate", "endDate"]

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

    this.sortRows()

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visibleRows > 0)
    }
  }

  sort() {
    this.sortRows()
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

    if (this.hasSortTarget) {
      this.sortTarget.value = "shortest_first"
    }

    this.filter()

    if (this.hasSearchTarget) {
      this.searchTarget.focus()
    }
  }

  sortRows() {
    if (!this.hasRowTarget) {
      return
    }

    const rows = [...this.rowTargets]
    const tbody = rows[0]?.parentElement
    const sortOrder = this.hasSortTarget ? this.sortTarget.value : "shortest_first"

    if (!tbody) {
      return
    }

    rows.sort((left, right) => {
      const leftValue = this.durationValue(left)
      const rightValue = this.durationValue(right)

      if (leftValue === null && rightValue === null) return 0
      if (leftValue === null) return 1
      if (rightValue === null) return -1

      return sortOrder === "longest_first" ? rightValue - leftValue : leftValue - rightValue
    })

    rows.forEach((row) => tbody.appendChild(row))
  }

  durationValue(row) {
    const rawValue = row.dataset.onboardingDurationDays

    if (rawValue === undefined || rawValue === "") {
      return null
    }

    const parsedValue = Number.parseFloat(rawValue)
    return Number.isNaN(parsedValue) ? null : parsedValue
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
