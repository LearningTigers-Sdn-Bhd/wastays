import { Controller } from "@hotwired/stimulus"

// Every row carries exactly one checkbox, so the controller makes no assumption
// about the markup around it. It used to filter on `closest('table')` because a
// second, duplicated mobile layout gave each record two checkboxes to keep in
// step.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "banner", "count", "idsInput"]

  connect() {
    this.update()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => { checkbox.checked = checked })
    this.update()
  }

  toggleSingle() {
    this.update()
  }

  clear() {
    this.checkboxTargets.forEach(checkbox => { checkbox.checked = false })
    this.update()
  }

  update() {
    const ids = this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.value)
    this.syncSelectAll(ids.length)
    this.syncBanner(ids)
  }

  syncSelectAll(selectedCount) {
    const total = this.checkboxTargets.length

    this.selectAllTargets.forEach(selectAll => {
      selectAll.checked = total > 0 && selectedCount === total
      selectAll.indeterminate = selectedCount > 0 && selectedCount < total
    })
  }

  syncBanner(ids) {
    const selected = ids.length > 0

    if (this.hasBannerTarget) {
      this.bannerTarget.classList.toggle("hidden", !selected)
      this.bannerTarget.classList.toggle("flex", selected)
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${ids.length} ${ids.length === 1 ? "guest" : "guests"} selected`
    }

    if (this.hasIdsInputTarget) {
      this.idsInputTarget.value = selected ? JSON.stringify(ids) : ""
    }
  }
}
