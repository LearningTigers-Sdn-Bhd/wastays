import { Controller } from "@hotwired/stimulus"

// Which selected rows a given action would actually change. "Mark VIP" skips
// the ones already VIP, so the confirm can say what really happens instead of
// claiming forty changes when only three land.
const WOULD_CHANGE = {
  vip: checkbox => checkbox.dataset.vip !== "true",
  unvip: checkbox => checkbox.dataset.vip === "true",
  blacklist: checkbox => checkbox.dataset.blacklisted !== "true",
  unblacklist: checkbox => checkbox.dataset.blacklisted === "true"
}

// Every row carries exactly one checkbox, so the controller makes no assumption
// about the markup around it. It used to filter on `closest('table')` because a
// second, duplicated mobile layout gave each record two checkboxes to keep in
// step.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "banner", "count", "idsInput", "action", "summary"]
  static values = { noun: { type: String, default: "item" } }

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
    const selected = this.checkboxTargets.filter(checkbox => checkbox.checked)

    this.syncSelectAll(selected.length)
    this.syncBanner(selected.map(checkbox => checkbox.value))
    this.syncPreviews(selected)
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
      this.countTarget.textContent = `${ids.length} ${this.noun(ids.length)} selected`
    }

    this.idsInputTargets.forEach(input => {
      input.value = selected ? JSON.stringify(ids) : ""
    })
  }

  // An action that would change nothing is disabled rather than left to fail
  // silently on the server.
  syncPreviews(selected) {
    this.actionTargets.forEach(action => {
      const { changed } = this.preview(action, selected)
      action.disabled = changed === 0
      action.setAttribute("aria-disabled", String(changed === 0))
      action.dataset.turboConfirm = this.sentence(action, selected)
    })

    this.summaryTargets.forEach(summary => {
      summary.textContent = this.sentence(summary, selected)
    })
  }

  preview(element, selected) {
    const decide = WOULD_CHANGE[element.dataset.bulkKind]
    const changed = decide ? selected.filter(decide).length : selected.length

    return { changed: changed, skipped: selected.length - changed, selected: selected.length }
  }

  sentence(element, selected) {
    const counts = this.preview(element, selected)
    let text = this.fill(element.dataset.bulkConfirm || "", counts)

    if (counts.skipped > 0 && element.dataset.bulkSkipped) {
      text = `${text} ${this.fill(element.dataset.bulkSkipped, counts)}`
    }

    return text.trim()
  }

  fill(template, counts) {
    return template
      .replaceAll("{changed}", counts.changed)
      .replaceAll("{skipped}", counts.skipped)
      .replaceAll("{selected}", counts.selected)
      .replaceAll("{noun}", this.noun(counts.changed))
      .replaceAll("{selectedNoun}", this.noun(counts.selected))
  }

  noun(count) {
    return count === 1 ? this.nounValue : `${this.nounValue}s`
  }
}
