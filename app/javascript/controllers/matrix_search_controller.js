import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "row"]

  search() {
    const query = this.queryTarget.value.toLowerCase().trim()

    this.rowTargets.forEach(row => {
      const name = (row.dataset.matrixSearchName || "").toLowerCase()
      if (query === "" || name.includes(query)) {
        row.classList.remove("hidden")
      } else {
        row.classList.add("hidden")
      }
    })
  }

  preventSubmit(event) {
    event.preventDefault()
  }
}
