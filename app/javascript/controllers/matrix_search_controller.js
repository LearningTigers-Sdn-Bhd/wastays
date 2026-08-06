import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "row", "empty", "status"]

  search() {
    const query = this.queryTarget.value.toLowerCase().trim()
    let matches = 0

    this.rowTargets.forEach(row => {
      const name = (row.dataset.matrixSearchName || "").toLowerCase()
      const visible = query === "" || name.includes(query)
      row.classList.toggle("hidden", !visible)
      if (visible) matches += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", matches > 0)
    if (this.hasStatusTarget && query !== "") {
      this.statusTarget.textContent = `${matches} ${matches === 1 ? "permission" : "permissions"} match ${query}.`
    }
  }
}
